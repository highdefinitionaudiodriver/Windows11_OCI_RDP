# OCI Ampere A1 - Windows 11 Pro ARM インストーラー

## 概要

Oracle Cloud Infrastructure (OCI) の **Always Free** Ampere A1 インスタンス (Ubuntu) を
**Windows 11 Pro ARM** に置き換えるツールです。

インストール後は **リモートデスクトップ (RDP)** で接続可能な状態になります。

---

## 🎯 これは何？（30秒で）

- **誰のため**：無料で Windows ARM 開発環境がほしい開発者／クラウド検証で OCI Always Free を活用したい個人
- **何が解決される**：OCI Always Free Ampere A1 (4 OCPU / 24 GB / 24/365 無料) を **Ubuntu から Windows 11 Pro ARM** に置換し、**RDP でアクセス可能なクラウド Windows 環境** を 0 円で構築
- **なぜ既存ツールではダメか**：MS Azure 等の Windows VM は月額課金。本ツールは **OCI の Always Free 枠** を最大活用し、ARM Windows のクラウド検証を無償化
- **使う条件**：OCI アカウント（Always Free 利用可能）／Ampere A1 インスタンス（Ubuntu）

## 💰 想定ユースケース・価格帯

| 用途 | 形態 |
|---|---|
| 個人検証・ARM 開発環境構築 | 無料（MIT） |
| 企業内検証用 Windows ARM 環境のセットアップ支援 | 応相談 |
| Windows ARM 上の動作検証・ハンズオン研修 | 応相談 |

> ⚠️ Microsoft の Windows ライセンス条項・OCI の利用規約を遵守してご利用ください。Windows のアクティベーションには別途ライセンスが必要です。

---

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

## トラブルシューティング（よくある質問 FAQ）

> 💡 OCI Ampere A1 + Windows 11 ARM インストールで遭遇しやすい問題と対処を、
> 実際の発生順にまとめています。

---

### Q1. RDP 接続できない

**症状**：`mstsc.exe` で接続するも応答なし／タイムアウト／黒画面。

**チェックリスト**：
1. **OCI セキュリティリストで TCP 3389 が許可されているか**
   - VCN → セキュリティリスト → イングレスルールで `0.0.0.0/0` または接続元 IP からの 3389 が許可されているか
   - **`setup-oci-security.sh` で自動設定可能**
2. **インスタンスのパブリック IP が正しいか** — 再起動でアドレスが変わることはないが、OCI コンソールで再確認
3. **Windows 初期設定が終わるまで 10 分以上待つ** — 初回起動はやや時間がかかる
4. **OS ファイアウォール** — autounattend.xml で RDP は許可済みだが、念のため OCI コンソール接続で `wf.msc` から確認

---

### Q2. インストールが途中で止まる（SSH セッションが切れる）

**症状**：`oci-win11-arm-installer.sh` の Step 5 (QEMU で Windows インストール) で SSH が切断される。

**原因**：通常、SSH のセッションタイムアウトか、ローカル PC のスリープ。

**対処**：
- **`tmux` / `screen` を使って実行する**：再接続しても継続される
  ```bash
  tmux new -s win11install
  ./oci-win11-arm-installer.sh
  # Ctrl-b d でデタッチ。あとで tmux attach -t win11install
  ```
- ローカル PC を **スリープさせない**設定にしておく
- 自宅回線が不安定なら、OCI 内の踏み台 VM 経由で実行することも検討

---

### Q3. メモリ不足エラー（QEMU が OOM Killer に殺される）

**症状**：Step 5 の途中で QEMU が突然終了し、`dmesg` に `Out of memory` ログ。

**原因**：Ampere A1 のシェイプが 24 GB 未満で構成されている。

**対処**：
- OCI コンソールでインスタンスのシェイプを **VM.Standard.A1.Flex / 4 OCPU / 24 GB** に再設定
- インスタンスの再起動で反映される

---

### Q4. ブートしない（再起動後 OCI コンソールに何も映らない）

**症状**：Step 7 で再起動後、OCI コンソール接続で画面が真っ黒。

**チェックリスト**：
1. **インスタンスのコンソール接続 (シリアル) で UEFI 起動ログを確認**
2. **`dd` でブートディスクへの書き込みが完了する前に再起動した可能性**
   - QEMU 仮想ディスク作成 → raw 変換 → `dd` の各ステップを再実行
3. **最悪のリカバリ**：ブートボリュームをデタッチして別 Ubuntu インスタンスに付け替え、ファイルを確認

---

### Q5. RDP に繋がるが「Black Screen of Death」

**症状**：RDP 接続成功 → ユーザー認証 → 真っ黒な画面のまま操作不能。

**対処**：
- `Ctrl + Alt + End` でセキュリティ画面を呼び出し、サインアウト → 再ログイン
- **VirtIO GPU ドライバ未適用** の可能性 → autounattend.xml の VirtIO セクションが正しいか確認
- Microsoft Update でグラフィックドライバを最新化

---

### Q6. キーボードレイアウトが英字になる

**症状**：日本語キーボードを設定したのに、`@` キーで `"` が入力されるなど。

**対処**：
- 設定 → 時刻と言語 → 言語と地域 → 日本語 → オプション → ハードウェアキーボードレイアウト → **日本語キーボード (106/109)** を選択
- 再起動で確実に反映

---

### Q7. Always Free の枠を超えていないか心配

**症状**：請求が発生しないか不安。

**対処**：
- OCI コンソール → 課金 → コスト分析 で現在の利用状況を確認
- **Ampere A1: 4 OCPU / 24 GB** までは無料枠内
- **ブートボリューム 200 GB / 月次 IO** に注意 — 200 GB を超えると課金対象
- **ネットワーク 10 TB/月送信** までは無料

---

### Q8. Windows のライセンス認証が通らない

**症状**：「Windows ライセンス認証」がエラー。

**対処**：
- **Windows 11 Pro ARM のライセンスは別途購入が必要**（本ツールは含めない）
- Microsoft 公式から購入したリテール版プロダクトキー、または MAK / KMS （企業向け）を入手
- 設定 → システム → ライセンス認証 で手動入力
- ARM 版のライセンス入手はやや特殊。MS パートナー or 法人 EA 経由が確実

---

### Q9. インスタンスを停止しても課金される

**症状**：停止したのに料金が発生。

**対処**：
- Ampere A1 は「**停止しても OCPU 容量は予約**」されるため Always Free 枠内でも警告が出ることがある
- 完全に停止したい場合は **インスタンスを終了 (Terminate) して再作成**
- ブートボリュームを保持して再アタッチすれば、再構築は早い

---

### Q10. 別の Windows ARM 版を使いたい（Windows 11 23H2 や Windows Server）

**対処**：
- `oci-win11-arm-installer.sh` の `ISO` パスと `autounattend.xml` のエディションを変更
- Windows 11 IoT Enterprise LTSC ARM、Windows Server 2025 ARM など、ARM64 ISO を用意すれば同じ手順で動く
- **autounattend.xml のエディション識別子（例: `Windows 11 Pro` → `Windows 11 IoT Enterprise LTSC`）を ISO の中身に合わせて修正**

---

> 💬 ここに無い問題があれば Issue でお知らせください。
> 解決事例を集めるほどこの FAQ が充実し、後続のユーザーが助かります。

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

---

## 🤝 商用利用・カスタマイズ依頼

- 個人・社内利用は無料（MIT ライセンス）
- 法人・自治体・SI 向け導入支援、カスタマイズ、診断レポート受託は応相談
- 連絡先：highdefinitionaudiodriver@gmail.com

<!-- CODEX-CURRENT-STATUS:START -->
## 現状サマリ (2026-05-25)

- 対象: OCI Ampere A1 - Windows 11 Pro ARM インストーラー
- 作業ブランチ: feat/sellable-v1
- README更新時点の参照コミット: 405b9c3 chore: add .gitignore to ignore claude directory
- README とリポジトリ内の既存ファイルを起点に継続作業可能。
- 主要な確認コマンド: README 記載のセットアップ・検証コマンド
- 次に進めるなら、README 内の利用手順と既存 docs / tests を起点に、未整備の検証手順・引き継ぎメモ・CI 化を補強する。
<!-- CODEX-CURRENT-STATUS:END -->

