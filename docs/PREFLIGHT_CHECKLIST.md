# OCI Windows 11 ARM 事前チェックリスト

このチェックリストは、`oci-win11-arm-installer.sh` を実行する前に確認する項目です。特に OCI Always Free 枠、RDP 開放、Windows ライセンス、SSH 切断対策を事前に潰すことで、インストール途中のやり直しを減らします。

## 1. OCI インスタンス

- [ ] シェイプが `VM.Standard.A1.Flex`
- [ ] OCPU は 4、メモリは 24 GB を推奨
- [ ] OS は Ubuntu ARM
- [ ] ブートボリュームに十分な空き容量がある
- [ ] インスタンスのパブリック IPv4 を控えた
- [ ] SSH ユーザー名と秘密鍵でログインできる

確認例:

```bash
ssh -i <秘密鍵> ubuntu@<OCI_PUBLIC_IP> "uname -m && free -h && df -h /"
```

期待値:

- `uname -m` が `aarch64`
- メモリが 20 GB 以上
- `/` に Windows ISO 展開分を含めた十分な空き容量

## 2. ネットワークとセキュリティ

- [ ] OCI セキュリティリストまたは NSG で TCP `3389` を開放済み
- [ ] 可能なら接続元 IP を自分のグローバル IP `/32` に絞る
- [ ] SSH の TCP `22` は作業元 IP から接続可能
- [ ] インストール中に SSH が切れても復帰できるよう `tmux` または `screen` を使う

RDP 開放補助:

```bash
bash setup-oci-security.sh
```

## 3. ローカル作業端末

- [ ] Windows 11 ARM ISO を用意済み
- [ ] ISO ファイルのパスに空白や日本語がある場合は引用符で囲む
- [ ] SSH 秘密鍵のパーミッションが適切
- [ ] RDP クライアントを用意済み

## 4. Windows ライセンスと利用規約

- [ ] Microsoft の Windows ライセンス条項を確認した
- [ ] OCI の Always Free 条件と課金条件を確認した
- [ ] Windows のアクティベーション方法を別途用意した

## 5. 実行直前

- [ ] `README.md` の手順を最後まで読んだ
- [ ] FAQ の「RDP 接続できない」「ブートしない」「Black Screen」を確認した
- [ ] 作業ログを残すため、ターミナルログを保存できる状態にした
- [ ] 長時間処理に備え、ローカル端末のスリープを無効化した

実行:

```bash
bash oci-win11-arm-installer.sh
```

## 6. 失敗時に集める情報

後続の調査やサポート依頼では、以下を控えてください。秘密鍵やパスワードは共有しないでください。

- OCI シェイプ、OCPU、メモリ
- Ubuntu の `uname -a`
- `free -h` と `df -h`
- 失敗したフェーズ名
- `remote-install.sh` の最後の 100 行程度のログ
- OCI コンソール接続で見える起動画面またはエラーメッセージ
