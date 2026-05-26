# Codex / Claude Code 引き継ぎメモ

## 対象

- リポジトリ: `Windows11_OCI_RDP`
- 作業元: `C:\Users\highd\Documents\Github\Windows11_OCI_RDP`
- 同期先: `G:\マイドライブ\claudecode\Windows11_OCI_RDP`

## 2026-05-26 Codex作業ログ

### 実行前チェックリストを追加

インストール途中の失敗や課金・RDP開放漏れを減らすため、`docs/PREFLIGHT_CHECKLIST.md` を追加し、README の Step 2 から参照するようにしました。

追加内容:

- OCI A1 Flex の OCPU / メモリ / Ubuntu ARM 確認
- SSH疎通、ディスク空き、`tmux` / `screen` 利用の推奨
- RDP TCP 3389 のセキュリティリスト / NSG 確認
- Windows ライセンスと OCI Always Free 条件の確認
- 実行直前と失敗時に集める情報のチェック項目

検証:

```powershell
bash -n oci-win11-arm-installer.sh
bash -n remote-install.sh
bash -n setup-oci-security.sh
```

## 次にやるとよいこと

1. `setup-oci-security.sh` に dry-run モードを追加する。
2. README にチェックリストのスクリーンショットまたは短い手順GIFのプレースホルダを置く。
3. 失敗ログのサンプルと切り分け表を `docs/troubleshooting/` に分離する。
