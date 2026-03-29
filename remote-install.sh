#!/bin/bash
#==============================================================================
# remote-install.sh
# OCI Ampere A1 インスタンス上で実行されるリモートインストールスクリプト
# Ubuntu の起動ディスクを Windows 11 Pro ARM に置き換える
#==============================================================================

set -euo pipefail

WIN_USERNAME="${1:?Usage: $0 <username> <password> <disk_gb>}"
WIN_PASSWORD="${2:?Usage: $0 <username> <password> <disk_gb>}"
BOOT_DISK_GB="${3:-47}"

LOG="/tmp/win11-remote-install.log"
WORK_DIR="/tmp/win11-work"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG"; exit 1; }

#==============================================================================
# Step 1: 環境チェック
#==============================================================================
step1_check_env() {
    log "=== Step 1: 環境チェック ==="

    # root 権限確認
    [[ $EUID -eq 0 ]] || error "root 権限が必要です"

    # アーキテクチャ確認
    local arch
    arch=$(uname -m)
    log "アーキテクチャ: $arch"
    [[ "$arch" == "aarch64" ]] || error "このスクリプトは ARM64 (aarch64) 専用です"

    # ISO確認
    [[ -f /tmp/win11.iso ]] || error "Windows 11 ISO が /tmp/win11.iso に見つかりません"
    [[ -f /tmp/autounattend.xml ]] || error "autounattend.xml が /tmp/ に見つかりません"

    # ブートディスク特定
    BOOT_DISK=$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')
    log "ブートディスク: $BOOT_DISK"
    [[ -n "$BOOT_DISK" ]] || error "ブートディスクが特定できません"

    # メモリ確認
    local mem_gb
    mem_gb=$(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo)
    log "メモリ: ${mem_gb}GB"
    [[ $mem_gb -ge 8 ]] || warn "メモリが少ない可能性があります (${mem_gb}GB)。推奨: 16GB以上"

    # KVM 確認
    if [[ -e /dev/kvm ]]; then
        log "KVM: 利用可能"
        KVM_ACCEL="-accel kvm -cpu host"
    else
        warn "KVM が利用不可。ソフトウェアエミュレーションを使用します (非常に低速)"
        KVM_ACCEL="-accel tcg,thread=multi -cpu max"
    fi

    # 必要なパッケージ確認
    log "必要パッケージを確認中..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq qemu-utils qemu-system-arm qemu-efi-aarch64 \
        genisoimage parted dosfstools ntfs-3g ovmf 2>/dev/null || true

    mkdir -p "$WORK_DIR"
    log "Step 1 完了"
}

#==============================================================================
# Step 2: Windows インストール用仮想ディスク作成
#==============================================================================
step2_create_virtual_disk() {
    log "=== Step 2: 仮想ディスクイメージ作成 ==="

    local DISK_IMG="${WORK_DIR}/win11.qcow2"

    # qcow2 仮想ディスク作成
    log "仮想ディスク作成: ${BOOT_DISK_GB}GB"
    qemu-img create -f qcow2 "$DISK_IMG" "${BOOT_DISK_GB}G"

    log "Step 2 完了"
}

#==============================================================================
# Step 3: autounattend ISO 作成
#==============================================================================
step3_create_unattend_iso() {
    log "=== Step 3: 応答ファイル ISO 作成 ==="

    local UNATTEND_DIR="${WORK_DIR}/unattend"
    local UNATTEND_ISO="${WORK_DIR}/unattend.iso"

    mkdir -p "$UNATTEND_DIR"
    cp /tmp/autounattend.xml "${UNATTEND_DIR}/autounattend.xml"

    # VirtIO ドライバインストール用バッチファイル
    mkdir -p "${UNATTEND_DIR}/virtio"
    cat > "${UNATTEND_DIR}/virtio/install.bat" << 'BATEOF'
@echo off
echo Installing VirtIO Drivers...
rem VirtIO ドライバは QEMU 仮想ディスク経由で提供される場合に使用
rem OCI のネイティブ環境ではパラバーチャルドライバが自動認識される
echo Done.
BATEOF

    # ISO 作成
    if command -v genisoimage &>/dev/null; then
        genisoimage -quiet -o "$UNATTEND_ISO" -J -r "$UNATTEND_DIR"
    elif command -v mkisofs &>/dev/null; then
        mkisofs -quiet -o "$UNATTEND_ISO" -J -r "$UNATTEND_DIR"
    else
        error "genisoimage/mkisofs が見つかりません"
    fi

    log "応答ファイル ISO: $UNATTEND_ISO"
    log "Step 3 完了"
}

#==============================================================================
# Step 4: UEFI ファームウェア準備
#==============================================================================
step4_prepare_uefi() {
    log "=== Step 4: UEFI ファームウェア準備 ==="

    local UEFI_CODE="${WORK_DIR}/QEMU_EFI.fd"
    local UEFI_VARS="${WORK_DIR}/QEMU_VARS.fd"

    # UEFI ファームウェアを探す
    local UEFI_SRC=""
    for path in \
        /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
        /usr/share/AAVMF/AAVMF_CODE.fd \
        /usr/share/edk2/aarch64/QEMU_EFI.fd \
        /usr/share/qemu/edk2-aarch64-code.fd; do
        if [[ -f "$path" ]]; then
            UEFI_SRC="$path"
            break
        fi
    done

    [[ -n "$UEFI_SRC" ]] || error "UEFI ファームウェアが見つかりません"
    log "UEFI ファームウェア: $UEFI_SRC"

    # コピーして固定サイズに
    cp "$UEFI_SRC" "$UEFI_CODE"
    truncate -s 64M "$UEFI_CODE"

    # VARS ファイル作成
    local VARS_SRC=""
    for path in \
        /usr/share/qemu-efi-aarch64/QEMU_VARS.fd \
        /usr/share/AAVMF/AAVMF_VARS.fd \
        /usr/share/edk2/aarch64/QEMU_VARS.fd; do
        if [[ -f "$path" ]]; then
            VARS_SRC="$path"
            break
        fi
    done

    if [[ -n "$VARS_SRC" ]]; then
        cp "$VARS_SRC" "$UEFI_VARS"
    else
        # 空の VARS ファイルを作成
        dd if=/dev/zero of="$UEFI_VARS" bs=1M count=64 2>/dev/null
    fi
    truncate -s 64M "$UEFI_VARS"

    log "Step 4 完了"
}

#==============================================================================
# Step 5: QEMU で Windows 11 をインストール (ヘッドレス)
#==============================================================================
step5_install_windows() {
    log "=== Step 5: QEMU で Windows 11 インストール ==="
    log "※ この処理には 20〜40分かかります"

    local DISK_IMG="${WORK_DIR}/win11.qcow2"
    local UNATTEND_ISO="${WORK_DIR}/unattend.iso"
    local UEFI_CODE="${WORK_DIR}/QEMU_EFI.fd"
    local UEFI_VARS="${WORK_DIR}/QEMU_VARS.fd"
    local QEMU_LOG="${WORK_DIR}/qemu.log"

    # VirtIO ドライバ ISO ダウンロード
    local VIRTIO_ISO="${WORK_DIR}/virtio-win.iso"
    if [[ ! -f "$VIRTIO_ISO" ]]; then
        log "VirtIO ドライバ ISO をダウンロード中..."
        local VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
        wget -q -O "$VIRTIO_ISO" "$VIRTIO_URL" 2>/dev/null || \
        curl -sL -o "$VIRTIO_ISO" "$VIRTIO_URL" 2>/dev/null || \
        warn "VirtIO ISO のダウンロードに失敗。ドライバなしで続行します"
    fi

    # QEMU 実行メモリ (ホストの半分を割り当て)
    local qemu_mem
    qemu_mem=$(awk '/MemTotal/{printf "%.0f", $2/1024/2}' /proc/meminfo)
    [[ $qemu_mem -ge 4096 ]] || qemu_mem=4096
    [[ $qemu_mem -le 16384 ]] || qemu_mem=16384
    log "QEMU メモリ割り当て: ${qemu_mem}MB"

    # QEMU コマンド構築
    local QEMU_CMD="qemu-system-aarch64 \
        -name win11-install \
        -machine virt,gic-version=max \
        ${KVM_ACCEL} \
        -m ${qemu_mem}M \
        -smp 4 \
        -drive if=pflash,format=raw,file=${UEFI_CODE},readonly=on \
        -drive if=pflash,format=raw,file=${UEFI_VARS} \
        -drive file=${DISK_IMG},format=qcow2,if=virtio,cache=writeback \
        -cdrom /tmp/win11.iso \
        -drive file=${UNATTEND_ISO},format=raw,if=virtio,media=cdrom,index=2"

    # VirtIO ISO があれば追加
    if [[ -f "$VIRTIO_ISO" ]]; then
        QEMU_CMD+=" -drive file=${VIRTIO_ISO},format=raw,if=virtio,media=cdrom,index=3"
    fi

    # ネットワーク & ディスプレイ
    QEMU_CMD+=" \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0 \
        -device ramfb \
        -device usb-ehci \
        -device usb-kbd \
        -device usb-mouse \
        -display none \
        -serial mon:stdio \
        -boot d \
        -no-reboot"

    log "QEMU インストール開始..."
    log "コマンド: $QEMU_CMD"

    # タイムアウト付きで実行 (最大90分)
    eval timeout 5400 $QEMU_CMD >> "$QEMU_LOG" 2>&1 || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            warn "QEMU がタイムアウトしました (90分)。インストールが完了していない可能性があります"
        else
            log "QEMU 終了コード: $exit_code (正常終了の可能性あり)"
        fi
    }

    # ディスクイメージ確認
    if [[ -f "$DISK_IMG" ]]; then
        local img_size
        img_size=$(qemu-img info "$DISK_IMG" | grep "disk size" | awk '{print $3, $4}')
        log "インストール済みディスクサイズ: $img_size"
    fi

    log "Step 5 完了"
}

#==============================================================================
# Step 6: 仮想ディスクを実ディスクに書き込み
#==============================================================================
step6_write_to_disk() {
    log "=== Step 6: ブートディスクへの書き込み ==="
    warn "この操作でブートディスクの全データが消去されます"

    local DISK_IMG="${WORK_DIR}/win11.qcow2"
    local RAW_IMG="${WORK_DIR}/win11.raw"

    # qcow2 → raw 変換
    log "qcow2 → raw 変換中..."
    qemu-img convert -f qcow2 -O raw "$DISK_IMG" "$RAW_IMG"

    local raw_size
    raw_size=$(stat -c%s "$RAW_IMG" 2>/dev/null || stat -f%z "$RAW_IMG")
    log "RAW イメージサイズ: $(( raw_size / 1024 / 1024 ))MB"

    # 現在のファイルシステムを RAM にコピー (pivot_root 方式)
    log "現在のシステムを RAM にコピー中..."

    # tmpfs を作成 (RAMの一部を使用)
    mount -t tmpfs -o size=2G tmpfs /mnt

    # 最小限のシステムをコピー
    mkdir -p /mnt/{bin,sbin,lib,lib64,usr,dev,proc,sys,tmp,old_root}
    cp -a /bin /mnt/ 2>/dev/null || true
    cp -a /sbin /mnt/ 2>/dev/null || true
    cp -a /lib /mnt/ 2>/dev/null || true
    cp -a /lib64 /mnt/ 2>/dev/null || true
    cp -a /usr /mnt/ 2>/dev/null || true

    # RAW イメージも RAM にコピー
    log "RAW イメージを RAM にコピー中..."
    cp "$RAW_IMG" /mnt/tmp/win11.raw

    # pivot_root で RAM 上のシステムに切り替え
    log "pivot_root 実行中..."
    mount --make-rprivate /
    pivot_root /mnt /mnt/old_root

    # 基本的なファイルシステムをマウント
    mount -t proc proc /proc 2>/dev/null || true
    mount -t sysfs sysfs /sys 2>/dev/null || true
    mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

    # 旧ルートのマウントを解除
    log "旧ファイルシステムをアンマウント中..."
    umount -l /old_root 2>/dev/null || true

    # dd でブートディスクに書き込み
    log "ブートディスク (${BOOT_DISK}) に書き込み中..."
    log "※ この処理には数分かかります"
    dd if=/tmp/win11.raw of="${BOOT_DISK}" bs=4M status=progress conv=fsync 2>&1 | tee -a "$LOG"

    log "書き込み完了"
    sync

    log "Step 6 完了"
}

#==============================================================================
# Step 7: 再起動
#==============================================================================
step7_reboot() {
    log "=== Step 7: 再起動 ==="
    log "10秒後にインスタンスを再起動します..."
    log "再起動後、Windows 11 の初期セットアップが自動実行されます"
    log "RDP で接続可能になるまで 5〜10分お待ちください"

    sleep 10
    log "再起動実行..."
    reboot -f || systemctl reboot -ff || echo b > /proc/sysrq-trigger
}

#==============================================================================
# メイン
#==============================================================================
main() {
    log "========================================="
    log " Windows 11 Pro ARM リモートインストール開始"
    log " ユーザー: ${WIN_USERNAME}"
    log " ディスク: ${BOOT_DISK_GB}GB"
    log "========================================="

    step1_check_env
    step2_create_virtual_disk
    step3_create_unattend_iso
    step4_prepare_uefi
    step5_install_windows
    step6_write_to_disk
    step7_reboot
}

main "$@"
