# Claude Code 引き継ぎメモ

`HANDOFF_FOR_CODEX.md` と同じ要点です。

## 2026-05-26 Codex作業

`docs/PREFLIGHT_CHECKLIST.md` を追加し、README の Step 2 からリンクしました。

狙い:

- OCI Always Free 枠の条件確認
- RDP 3389 開放漏れ防止
- SSH 切断対策
- Windows ライセンス確認
- 失敗時に必要なログ収集の標準化

確認済み:

```powershell
bash -n oci-win11-arm-installer.sh
bash -n remote-install.sh
bash -n setup-oci-security.sh
```

次は `setup-oci-security.sh` の dry-run モード追加がよいです。
