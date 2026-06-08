# GitHub Release 作成スニペット（PowerShell）。
# 事前に gh auth login 済みであること。タグ未作成なら gh が作成する。
# repo: https://github.com/highdefinitionaudiodriver/Windows11_OCI_RDP
$ver = 'v0.1.0'
$notes = Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\RELEASE_NOTES.md"
gh release create $ver `
  --title "Windows11 on OCI RDP 構築スクリプト $ver" `
  --notes "$notes" `
  # 配布物を添付する場合は末尾にファイルパスを列挙: （添付資産があれば指定）
