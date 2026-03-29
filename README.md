# OCI Ampere A1 - Windows 11 Pro ARM インストーラー

## 概要

Oracle Cloud Infrastructure (OCI) の **Always Free** Ampere A1 インスタンス (Ubuntu) を
**Windows 11 Pro ARM** に置き換えるツールです。

インストール後は **リモートデスクトップ (RDP)** で接続可能な状態になります。

## 対象スペック

| 項目 | 値 |
|------|-----|
| シェイプ | VM.Standard.A1.Flex |
| CPU | Ampere Altra (ARM64) 4 OCPU |
| メモリ | 24 GB |
| ネットワーク | 4 Gbps |
| ブートボリューム | 47 GB (デフォルト) |
| OS (変更前) | Ubuntu 22.04+ ARM64 |
| OS (変更後) | Windows 11 Pro ARM (25H2) |

## 必要な事前準備

### 1. OCI 側

- OCI Ampere A1 インスタンスが作成済み (Ubuntu)
- SSH 接続が可能
- **セキュリティリスト / NSG で TCP 3389 (RDP) を開放済み**

```
セキュリティリスト → イングレス・ルール追加:
  ソースCIDR: 0.0.0.0/0 (または接続元IP)
  プロトコル: TCP
  宛先ポート: 3389
```

### 2. ローカル PC 側

- Bash が実行可能 (Linux / macOS / WSL / Git Bash)
- `ssh` / `scp` コマンドが利用可能
- OCI インスタンスへの SSH 秘密鍵
- Windows 11 ARM ISO ファイル (`ISO/` ディレクトリに配置)

## ファイル構成

```
Windows11_OCI_RDP/
├── oci-win11-arm-installer.sh   # メインスクリプト (ローカルで実行)
├── remote-install.sh            # リモートスクリプト (OCI上で自動実行)
├── setup-oci-security.sh        # OCI セキュリティリスト設定補助
├── ISO/
│   └── Win11_25H2_Japanese_Arm64_v2.iso
└── README.md
```

## 使い方

### Step 1: 実行権限付与

```bash
chmod +x oci-win11-arm-installer.sh remote-install.sh
```

### Step 2: インストーラー実行

```bash
./oci-win11-arm-installer.sh
```

### Step 3: ウィザードに従って入力

ウィザードで以下を入力します:

1. **OCI インスタンスのパブリック IP**
2. **SSH ユーザー名** (デフォルト: ubuntu)
3. **SSH 秘密鍵パス** (デフォルト: ~/.ssh/id_rsa)
4. **Windows ユーザー名** (RDPログイン用)
5. **Windows パスワード** (RDPログイン用)
6. **Windows 11 ISO パス** (デフォルト: ./ISO/Win11_25H2...iso)

### Step 4: 自動インストール (30〜60分)

以下が自動実行されます:
1. ISO と設定ファイルを OCI インスタンスに転送
2. QEMU + KVM で Windows 11 を仮想ディスクにインストール
3. autounattend.xml による無人セットアップ
4. 仮想ディスクをブートディスクに dd 書き込み
5. インスタンス再起動

### Step 5: RDP 接続

再起動後 5〜10 分待ってから:

```
リモートデスクトップ接続:
  コンピューター: <OCI パブリック IP>
  ユーザー名:     <ウィザードで設定したユーザー名>
  パスワード:     <ウィザードで設定したパスワード>
```

## 処理フロー図

```
ローカル PC                          OCI Ampere A1 インスタンス
============                         ==========================

[ウィザード実行]
    │
    ├─ autounattend.xml 生成
    │  (ユーザーID/PW埋め込み)
    │  (RDP有効化設定)
    │
    ├─ SSH 接続テスト ─────────────────→ Ubuntu ARM64
    │
    ├─ ISO アップロード ──────────────→ /tmp/win11.iso
    │
    ├─ 設定ファイル転送 ─────────────→ /tmp/autounattend.xml
    │                                    /tmp/remote-install.sh
    │
    └─ リモート実行 ─────────────────→ [Step 1] 環境チェック & パッケージ
                                        [Step 2] 仮想ディスク作成
                                        [Step 3] 応答ファイルISO作成
                                        [Step 4] UEFI FW 準備
                                        [Step 5] QEMU で Win11 インストール
                                               (autounattend.xml で無人実行)
                                               - ユーザーアカウント作成
                                               - RDP 有効化
                                               - ファイアウォール設定
                                               - VirtIO ドライバ
                                        [Step 6] qcow2→raw→dd ブートディスク
                                               (pivot_root でRAM上から書込)
                                        [Step 7] 再起動
                                                    │
                                                    ▼
                                        Windows 11 Pro ARM 起動
                                        RDP 接続可能状態
```

## 自動設定される項目

| 項目 | 設定値 |
|------|--------|
| OS | Windows 11 Pro ARM (日本語) |
| タイムゾーン | Tokyo Standard Time |
| キーボード | 日本語 (106/109) |
| ユーザーアカウント | ウィザードで指定 (管理者権限) |
| RDP | 有効 (ポート 3389) |
| ファイアウォール | RDP ルール許可済み |
| NLA | 無効 (互換性重視) |
| 電源設定 | スリープ無効 |
| コンピュータ名 | OCI-WIN11 |

## トラブルシューティング

### RDP 接続できない

1. OCI セキュリティリストで TCP 3389 が開放されているか確認
2. OCI コンソール接続でインスタンスの状態を確認
3. 再起動後 10 分以上待つ (Windows 初期設定中の可能性)

### インストールが途中で止まる

- SSH 接続が切断された場合: OCI コンソール接続で状態確認
- メモリ不足: 24GB RAM が割り当てられているか確認

### ブートしない

- OCI コンソール接続で画面を確認
- UEFI ブートが正常か確認
- 最悪の場合: ブートボリュームを再作成して Ubuntu を再インストール

## 注意事項

- このツールは **ブートディスクの全データを消去** します
- Windows 11 のライセンスは別途必要です
- OCI の利用規約を確認の上、自己責任でご利用ください
- Always Free 枠のリソース上限に注意してください

## 参考リンク

- [OCI Arm-Based Compute](https://docs.oracle.com/en-us/iaas/Content/Compute/References/arm.htm)
- [Windows 11 on Ampere (GitHub)](https://github.com/AmpereComputing/Windows-11-On-Ampere)
- [VirtIO ARM64 QEMU Guide](https://virtio-win.github.io/Knowledge-Base/Windows-arm64-vm-using-qemu.html)
- [Oracle VirtIO Drivers](https://docs.oracle.com/en/operating-systems/oracle-linux/kvm-virtio/)
