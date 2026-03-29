#!/bin/bash
#==============================================================================
# OCI セキュリティリスト設定補助スクリプト
# RDP (TCP 3389) のイングレスルールを追加
#==============================================================================
# 前提: OCI CLI がインストール・設定済み
#==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  OCI セキュリティリスト - RDP ポート開放ツール          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# OCI CLI 確認
if ! command -v oci &>/dev/null; then
    echo -e "${RED}OCI CLI がインストールされていません${NC}"
    echo ""
    echo "=== 手動設定手順 ==="
    echo ""
    echo "1. OCI コンソール (https://cloud.oracle.com) にログイン"
    echo "2. [ネットワーキング] → [仮想クラウド・ネットワーク] を開く"
    echo "3. 対象の VCN を選択"
    echo "4. [セキュリティ・リスト] → デフォルトのセキュリティ・リストを選択"
    echo "5. [イングレス・ルールの追加] をクリック"
    echo ""
    echo "   ┌─────────────────────────────────────────┐"
    echo "   │ ソースCIDR:        0.0.0.0/0            │"
    echo "   │ IPプロトコル:      TCP                   │"
    echo "   │ ソース・ポート範囲: All                   │"
    echo "   │ 宛先ポート範囲:    3389                  │"
    echo "   │ 説明:              RDP Access             │"
    echo "   └─────────────────────────────────────────┘"
    echo ""
    echo -e "${YELLOW}セキュリティ推奨: ソースCIDR を自分のIPに限定してください${NC}"
    echo "  例: 203.0.113.50/32 (自分のグローバルIP)"
    echo ""
    echo "現在のグローバルIP確認:"
    curl -s ifconfig.me 2>/dev/null && echo "" || echo "(確認できませんでした)"
    exit 0
fi

# OCI CLI が使える場合の自動設定
echo "OCI CLI が検出されました。自動設定を行います。"
echo ""

# コンパートメントID
read -rp "コンパートメント OCID: " COMPARTMENT_ID
if [[ -z "$COMPARTMENT_ID" ]]; then
    echo -e "${RED}コンパートメント OCID が必要です${NC}"
    exit 1
fi

# VCN 一覧
echo ""
echo "VCN 一覧を取得中..."
oci network vcn list --compartment-id "$COMPARTMENT_ID" --query 'data[*].{name:"display-name",id:id}' --output table

read -rp "VCN OCID: " VCN_ID

# セキュリティリスト一覧
echo ""
echo "セキュリティリスト一覧を取得中..."
oci network security-list list --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" \
    --query 'data[*].{name:"display-name",id:id}' --output table

read -rp "セキュリティリスト OCID: " SECLIST_ID

# ソースCIDR
echo ""
echo -e "${YELLOW}セキュリティ推奨: 接続元IPを限定してください${NC}"
MY_IP=$(curl -s ifconfig.me 2>/dev/null || echo "")
if [[ -n "$MY_IP" ]]; then
    echo "現在のグローバルIP: $MY_IP"
    read -rp "ソースCIDR [${MY_IP}/32]: " SOURCE_CIDR
    SOURCE_CIDR="${SOURCE_CIDR:-${MY_IP}/32}"
else
    read -rp "ソースCIDR [0.0.0.0/0]: " SOURCE_CIDR
    SOURCE_CIDR="${SOURCE_CIDR:-0.0.0.0/0}"
fi

# 現在のルールを取得して RDP ルールを追加
echo ""
echo "RDP ルールを追加中..."

CURRENT_RULES=$(oci network security-list get --security-list-id "$SECLIST_ID" \
    --query 'data."ingress-security-rules"' 2>/dev/null)

# 新しいルールを追加
NEW_RULE="{\"source\": \"${SOURCE_CIDR}\", \"protocol\": \"6\", \"isStateless\": false, \"tcpOptions\": {\"destinationPortRange\": {\"min\": 3389, \"max\": 3389}}, \"description\": \"RDP Access for Windows 11\"}"

if echo "$CURRENT_RULES" | grep -q "3389"; then
    echo -e "${YELLOW}RDP ルール (3389) は既に存在します${NC}"
else
    UPDATED_RULES=$(echo "$CURRENT_RULES" | sed "s/^\[/[${NEW_RULE},/")

    oci network security-list update \
        --security-list-id "$SECLIST_ID" \
        --ingress-security-rules "$UPDATED_RULES" \
        --force

    echo -e "${GREEN}RDP ルールを追加しました${NC}"
fi

echo ""
echo -e "${GREEN}完了!${NC}"
echo "  ソースCIDR: $SOURCE_CIDR"
echo "  ポート:     TCP 3389"
