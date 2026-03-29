#!/bin/bash
#==============================================================================
# OCI Ampere A1 (ARM) - Windows 11 Pro ARM インストーラー
#==============================================================================
# 概要:
#   OCI の Ubuntu ARM インスタンス上で実行し、ブートディスクを
#   Windows 11 Pro ARM に置き換えるツール。
#
# 前提条件:
#   - OCI VM.Standard.A1.Flex (4 OCPU / 24GB RAM)
#   - Ubuntu 22.04+ ARM64 がインストール済み
#   - SSH でroot権限アクセス可能
#   - Windows 11 ARM ISO が /tmp/win11.iso に配置済み
#   - OCI セキュリティリストで TCP 3389 (RDP) が開放済み
#
# 使い方:
#   1. ローカルPCで setup.sh を実行 (ウィザード + ファイル転送)
#   2. OCI インスタンス上で自動的にインストールが実行される
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/oci-win11-install.log"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

#==============================================================================
# Phase 0: ウィザード - ユーザー情報収集
#==============================================================================
wizard() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   OCI Ampere A1 - Windows 11 Pro ARM インストーラー        ║"
    echo "║   VM.Standard.A1.Flex (4 OCPU / 24GB RAM / 4Gbps)         ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║   Windows 11 Pro ARM をインストールし、RDP接続を           ║"
    echo "║   有効にした状態でセットアップします。                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    # --- OCI インスタンス接続情報 ---
    echo -e "${CYAN}=== OCI インスタンス接続情報 ===${NC}"
    read -rp "OCI インスタンスのパブリックIP: " OCI_IP
    if [[ -z "$OCI_IP" ]]; then error "IPアドレスが入力されていません"; fi

    read -rp "SSH ユーザー名 [ubuntu]: " SSH_USER
    SSH_USER="${SSH_USER:-ubuntu}"

    read -rp "SSH 秘密鍵のパス [~/.ssh/id_rsa]: " SSH_KEY
    SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
    if [[ ! -f "$SSH_KEY" ]]; then error "SSH秘密鍵が見つかりません: $SSH_KEY"; fi

    echo ""
    echo -e "${CYAN}=== Windows 11 ユーザーアカウント設定 ===${NC}"
    echo "※ このアカウントでリモートデスクトップ(RDP)接続します"
    echo ""

    # --- Windows ユーザー名 ---
    while true; do
        read -rp "Windows ユーザー名 (英数字, 3文字以上): " WIN_USERNAME
        if [[ "$WIN_USERNAME" =~ ^[a-zA-Z][a-zA-Z0-9_]{2,19}$ ]]; then
            break
        else
            echo -e "${RED}無効なユーザー名です。英字で始まり、英数字・アンダースコアのみ、3〜20文字${NC}"
        fi
    done

    # --- Windows パスワード ---
    while true; do
        echo "パスワード要件: 8文字以上、大文字/小文字/数字/記号のうち3種以上"
        read -rsp "Windows パスワード: " WIN_PASSWORD
        echo ""
        read -rsp "パスワード確認: " WIN_PASSWORD_CONFIRM
        echo ""

        if [[ "$WIN_PASSWORD" != "$WIN_PASSWORD_CONFIRM" ]]; then
            echo -e "${RED}パスワードが一致しません${NC}"
            continue
        fi

        if [[ ${#WIN_PASSWORD} -lt 8 ]]; then
            echo -e "${RED}パスワードは8文字以上必要です${NC}"
            continue
        fi

        # 複雑性チェック
        complexity=0
        [[ "$WIN_PASSWORD" =~ [a-z] ]] && ((complexity++))
        [[ "$WIN_PASSWORD" =~ [A-Z] ]] && ((complexity++))
        [[ "$WIN_PASSWORD" =~ [0-9] ]] && ((complexity++))
        [[ "$WIN_PASSWORD" =~ [^a-zA-Z0-9] ]] && ((complexity++))

        if [[ $complexity -lt 3 ]]; then
            echo -e "${RED}パスワードの複雑性が不足しています (大文字/小文字/数字/記号のうち3種以上)${NC}"
            continue
        fi
        break
    done

    # --- Windows 11 ISO パス ---
    echo ""
    echo -e "${CYAN}=== Windows 11 ARM ISO ===${NC}"
    DEFAULT_ISO="${SCRIPT_DIR}/ISO/Win11_25H2_Japanese_Arm64_v2.iso"
    read -rp "Windows 11 ARM ISO パス [${DEFAULT_ISO}]: " WIN_ISO
    WIN_ISO="${WIN_ISO:-$DEFAULT_ISO}"
    if [[ ! -f "$WIN_ISO" ]]; then error "ISOファイルが見つかりません: $WIN_ISO"; fi

    # --- ブートディスクサイズ ---
    read -rp "ブートボリュームサイズ (GB) [47]: " BOOT_DISK_GB
    BOOT_DISK_GB="${BOOT_DISK_GB:-47}"

    echo ""
    echo -e "${CYAN}=== 設定確認 ===${NC}"
    echo "  OCI IP:          $OCI_IP"
    echo "  SSH ユーザー:    $SSH_USER"
    echo "  SSH 鍵:          $SSH_KEY"
    echo "  Windows ユーザー: $WIN_USERNAME"
    echo "  Windows パスワード: ********"
    echo "  ISO:             $WIN_ISO"
    echo "  ディスクサイズ:  ${BOOT_DISK_GB}GB"
    echo ""
    read -rp "この設定でインストールを開始しますか? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "キャンセルしました"
        exit 0
    fi

    # 設定をファイルに保存
    cat > /tmp/oci-win11-config.env << ENVEOF
OCI_IP="${OCI_IP}"
SSH_USER="${SSH_USER}"
SSH_KEY="${SSH_KEY}"
WIN_USERNAME="${WIN_USERNAME}"
WIN_PASSWORD="${WIN_PASSWORD}"
WIN_ISO="${WIN_ISO}"
BOOT_DISK_GB="${BOOT_DISK_GB}"
ENVEOF
}

#==============================================================================
# autounattend.xml 生成
#==============================================================================
generate_autounattend() {
    local username="$1"
    local password="$2"
    local disk_size_mb=$(( ${3:-47} * 1024 ))

    cat << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">

  <!-- =========================================== -->
  <!-- Phase 1: windowsPE - ディスク構成 & インストール -->
  <!-- =========================================== -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <SetupUILanguage>
        <UILanguage>ja-JP</UILanguage>
      </SetupUILanguage>
      <InputLocale>0411:00000411</InputLocale>
      <SystemLocale>ja-JP</SystemLocale>
      <UILanguage>ja-JP</UILanguage>
      <UserLocale>ja-JP</UserLocale>
    </component>

    <component name="Microsoft-Windows-Setup"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

      <!-- TPM/SecureBoot/RAM 要件バイパス -->
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>2</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>3</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>

      <!-- ディスク構成 (UEFI / GPT) -->
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <!-- EFI System Partition -->
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>EFI</Type>
              <Size>260</Size>
            </CreatePartition>
            <!-- MSR -->
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>MSR</Type>
              <Size>128</Size>
            </CreatePartition>
            <!-- Windows -->
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Format>FAT32</Format>
              <Label>EFI</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order>
              <PartitionID>3</PartitionID>
              <Format>NTFS</Format>
              <Label>Windows</Label>
              <Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/NAME</Key>
              <Value>Windows 11 Pro</Value>
            </MetaData>
          </InstallFrom>
        </OSImage>
      </ImageInstall>

      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey>
          <WillShowUI>OnError</WillShowUI>
        </ProductKey>
      </UserData>
    </component>
  </settings>

  <!-- =========================================== -->
  <!-- Phase 2: specialize - システム設定           -->
  <!-- =========================================== -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <InputLocale>0411:00000411</InputLocale>
      <SystemLocale>ja-JP</SystemLocale>
      <UILanguage>ja-JP</UILanguage>
      <UserLocale>ja-JP</UserLocale>
    </component>

    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <ComputerName>OCI-WIN11</ComputerName>
      <TimeZone>Tokyo Standard Time</TimeZone>
    </component>

    <!-- RDP 有効化 -->
    <component name="Microsoft-Windows-TerminalServices-LocalSessionManager"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <fDenyTSConnections>false</fDenyTSConnections>
    </component>

    <component name="Microsoft-Windows-TerminalServices-RDP-WinStationExtensions"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <UserAuthentication>0</UserAuthentication>
    </component>

    <!-- ファイアウォール: RDP ポート 3389 開放 -->
    <component name="Networking-MPSSVC-Svc"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <FirewallGroups>
        <FirewallGroup wcm:action="add" wcm:keyValue="RemoteDesktop">
          <Active>true</Active>
          <Group>@FirewallAPI.dll,-28752</Group>
          <Profile>all</Profile>
        </FirewallGroup>
      </FirewallGroups>
    </component>
  </settings>

  <!-- =========================================== -->
  <!-- Phase 3: oobeSystem - ユーザーアカウント     -->
  <!-- =========================================== -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <InputLocale>0411:00000411</InputLocale>
      <SystemLocale>ja-JP</SystemLocale>
      <UILanguage>ja-JP</UILanguage>
      <UserLocale>ja-JP</UserLocale>
    </component>

    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>

      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>%%WIN_USERNAME%%</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>%%WIN_PASSWORD%%</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>

      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>%%WIN_USERNAME%%</Username>
        <Password>
          <Value>%%WIN_PASSWORD%%</Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>3</LogonCount>
      </AutoLogon>

      <!-- 初回起動時の自動設定スクリプト -->
      <FirstLogonCommands>
        <!-- RDP を確実に有効化 -->
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f</CommandLine>
          <Description>Enable RDP</Description>
        </SynchronousCommand>
        <!-- NLA (Network Level Authentication) を無効化して互換性向上 -->
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f</CommandLine>
          <Description>Disable NLA</Description>
        </SynchronousCommand>
        <!-- ファイアウォール RDP ルール有効化 -->
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>netsh advfirewall firewall set rule group="リモート デスクトップ" new enable=yes</CommandLine>
          <Description>Enable RDP Firewall Rule (JA)</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>4</Order>
          <CommandLine>netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes</CommandLine>
          <Description>Enable RDP Firewall Rule (EN)</Description>
        </SynchronousCommand>
        <!-- RDP サービス自動起動 -->
        <SynchronousCommand wcm:action="add">
          <Order>5</Order>
          <CommandLine>sc config TermService start=auto</CommandLine>
          <Description>Set RDP Service Auto Start</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>6</Order>
          <CommandLine>net start TermService</CommandLine>
          <Description>Start RDP Service</Description>
        </SynchronousCommand>
        <!-- VirtIO ネットワークドライバのインストール (存在する場合) -->
        <SynchronousCommand wcm:action="add">
          <Order>7</Order>
          <CommandLine>cmd /c "if exist D:\virtio\install.bat D:\virtio\install.bat"</CommandLine>
          <Description>Install VirtIO Drivers</Description>
        </SynchronousCommand>
        <!-- 電源設定: スリープ無効 -->
        <SynchronousCommand wcm:action="add">
          <Order>8</Order>
          <CommandLine>powercfg -change -standby-timeout-ac 0</CommandLine>
          <Description>Disable Sleep</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>9</Order>
          <CommandLine>powercfg -change -monitor-timeout-ac 0</CommandLine>
          <Description>Disable Monitor Timeout</Description>
        </SynchronousCommand>
        <!-- 自動ログオン解除 (セキュリティ) -->
        <SynchronousCommand wcm:action="add">
          <Order>10</Order>
          <CommandLine>reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 0 /f</CommandLine>
          <Description>Disable AutoLogon After Setup</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
XMLEOF
}

#==============================================================================
# Phase 1: OCI インスタンスへのファイル転送と前準備
#==============================================================================
phase1_prepare_remote() {
    source /tmp/oci-win11-config.env
    local SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

    log "=== Phase 1: OCI インスタンスの準備 ==="

    # 接続テスト
    log "SSH 接続テスト..."
    ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${OCI_IP}" "echo 'SSH OK'" || \
        error "SSH接続に失敗しました: ${SSH_USER}@${OCI_IP}"

    # autounattend.xml を生成してユーザー情報を埋め込む
    log "autounattend.xml を生成中..."
    local AUTOUNATTEND_TMP="/tmp/autounattend.xml"
    generate_autounattend "$WIN_USERNAME" "$WIN_PASSWORD" "$BOOT_DISK_GB" | \
        sed "s/%%WIN_USERNAME%%/${WIN_USERNAME}/g" | \
        sed "s|%%WIN_PASSWORD%%|${WIN_PASSWORD}|g" > "$AUTOUNATTEND_TMP"

    # リモートに必要なパッケージをインストール
    log "リモートに必要パッケージをインストール中..."
    ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${OCI_IP}" "sudo bash -s" << 'REMOTE_PREP'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq qemu-utils qemu-system-arm qemu-efi-aarch64 \
    genisoimage wimtools parted dosfstools ntfs-3g ovmf cloud-image-utils 2>/dev/null || true
echo "PACKAGES_INSTALLED"
REMOTE_PREP

    # ファイル転送
    log "Windows 11 ISO をアップロード中 (約7.6GB - 時間がかかります)..."
    scp $SSH_OPTS -i "$SSH_KEY" "$WIN_ISO" "${SSH_USER}@${OCI_IP}:/tmp/win11.iso"

    log "autounattend.xml をアップロード中..."
    scp $SSH_OPTS -i "$SSH_KEY" "$AUTOUNATTEND_TMP" "${SSH_USER}@${OCI_IP}:/tmp/autounattend.xml"

    # リモートインストールスクリプトを転送
    log "インストールスクリプトをアップロード中..."
    scp $SSH_OPTS -i "$SSH_KEY" "${SCRIPT_DIR}/remote-install.sh" "${SSH_USER}@${OCI_IP}:/tmp/remote-install.sh"

    log "Phase 1 完了: ファイル転送が完了しました"
}

#==============================================================================
# Phase 2: リモートでインストール実行
#==============================================================================
phase2_run_remote_install() {
    source /tmp/oci-win11-config.env
    local SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 -o ServerAliveCountMax=120"

    log "=== Phase 2: リモートインストール実行 ==="
    warn "この処理には30〜60分かかります。SSH接続を切らないでください。"
    echo ""

    ssh $SSH_OPTS -i "$SSH_KEY" "${SSH_USER}@${OCI_IP}" \
        "sudo bash /tmp/remote-install.sh '${WIN_USERNAME}' '${WIN_PASSWORD}' '${BOOT_DISK_GB}'"

    log "Phase 2 完了"
}

#==============================================================================
# メイン処理
#==============================================================================
main() {
    echo ""
    log "OCI Windows 11 ARM インストーラーを開始します"
    echo ""

    # ウィザード実行
    wizard

    # remote-install.sh が存在するか確認
    if [[ ! -f "${SCRIPT_DIR}/remote-install.sh" ]]; then
        error "remote-install.sh が見つかりません: ${SCRIPT_DIR}/remote-install.sh"
    fi

    # Phase 1: 準備 & ファイル転送
    phase1_prepare_remote

    # Phase 2: リモートインストール
    phase2_run_remote_install

    # 完了メッセージ
    source /tmp/oci-win11-config.env
    echo ""
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              インストール完了!                              ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                            ║"
    echo "║  Windows 11 Pro ARM がインストールされました。             ║"
    echo "║  インスタンスは自動的に再起動されます。                    ║"
    echo "║                                                            ║"
    echo "║  === リモートデスクトップ接続情報 ===                      ║"
    echo "║                                                            ║"
    echo "║  IP アドレス: ${OCI_IP}                                    "
    echo "║  ユーザー名:  ${WIN_USERNAME}                              "
    echo "║  パスワード:  (ウィザードで設定したもの)                   "
    echo "║  ポート:      3389                                         ║"
    echo "║                                                            ║"
    echo "║  ※ 再起動後、Windows の初期セットアップに5〜10分          ║"
    echo "║    かかる場合があります。                                   ║"
    echo "║                                                            ║"
    echo "║  ※ OCI のセキュリティリストで TCP 3389 が                 ║"
    echo "║    開放されていることを確認してください。                   ║"
    echo "║                                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # クリーンアップ
    rm -f /tmp/oci-win11-config.env /tmp/autounattend.xml
}

main "$@"
