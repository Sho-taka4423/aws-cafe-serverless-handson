#!/usr/bin/env bash
# 正常な環境に、ハンズオン用の3つの障害を仕込む
#   #1 Lambda コードのバグ（/menu が 502）
#   #2 開店前の予約伝票を DynamoDB に入れ、Lambda の IAM ロールから dynamodb:Scan（伝票を読む権限）を外す
#   #3 /orders の OPTIONS（CORS プリフライト）を削除して API を再デプロイ
#   使い方: ./scripts/break-environment.sh team01 [team02 ...]
source "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || { echo "使い方: $0 <環境ID> [環境ID ...]"; exit 1; }

TODAY=$(TZ=Asia/Tokyo date +%Y-%m-%d)

# 開店前に届いている予約伝票（#2 で「伝票はあるのに表示されない」状態を作るため）
seed_orders() { # seed_orders <テーブル名>
  local t=$1
  put() {
    aws dynamodb put-item --table-name "$t" --item \
      "{\"orderId\":{\"S\":\"$1\"},\"item\":{\"S\":\"$2\"},\"size\":{\"S\":\"$3\"},\"customer\":{\"S\":\"$4\"},\"createdAt\":{\"S\":\"${TODAY}T$5+09:00\"}}"
  }
  put rsv-001 "アメリカーノ" L "佐藤" 07:45:00
  put rsv-002 "抹茶ラテ"     M "鈴木" 07:52:00
  put rsv-003 "ホットココア" S "田中" 08:03:00
}

for team in "$@"; do
  fn=$(output "$team" FunctionName)
  role=$(output "$team" RoleName)
  table=$(output "$team" TableName)
  api=$(output "$team" RestApiId)

  log "$team: #1 Lambda に障害入りコードを反映"
  update_code "$fn" "$REPO_DIR/lambda/broken/index.py"

  log "$team: #2 伝票を予約分だけにして、IAM ロールから Scan（読む権限）を外す"
  for id in $(aws dynamodb scan --table-name "$table" --query "Items[].orderId.S" --output text); do
    aws dynamodb delete-item --table-name "$table" --key "{\"orderId\":{\"S\":\"$id\"}}"
  done
  seed_orders "$table"
  role_policy "$role" "$(table_arn "$table")" "dynamodb:PutItem"

  log "$team: #3 /orders の OPTIONS を削除して API を再デプロイ"
  rid=$(orders_resource_id "$api")
  aws apigateway delete-method --rest-api-id "$api" --resource-id "$rid" --http-method OPTIONS 2>/dev/null || true
  redeploy_api "$api" "broken for hands-on"

  log "$team: 障害の仕込み完了"
done
echo
log "API の反映に数十秒かかることがあります。少し待ってから状態確認: ./scripts/verify.sh $*"
