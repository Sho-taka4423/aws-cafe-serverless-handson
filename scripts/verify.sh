#!/usr/bin/env bash
# 各チーム環境の状態（どのチャレンジが直っているか）を表示する。データは書き込まない
#   使い方: ./scripts/verify.sh team01 [team02 ...]
source "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || { echo "使い方: $0 <環境ID> [環境ID ...]"; exit 1; }

mark() { [ "$1" = ok ] && echo "✅ 正常" || echo "❌ 障害あり ($2)"; }

for team in "$@"; do
  url=$(output "$team" ApiUrl)
  role=$(output "$team" RoleName)
  table=$(output "$team" TableName)
  echo "=== $team  $url"

  menu=$(curl -s -o /dev/null -w "%{http_code}" "$url/menu")
  [ "$menu" = 200 ] && s=ok || s=ng
  echo "  #1 GET /menu            : $(mark $s "HTTP $menu")"

  if aws iam get-role-policy --role-name "$role" --policy-name OrdersTableAccess \
       --query PolicyDocument --output json | grep -q "dynamodb:Scan"; then s=ok; else s=ng; fi
  echo "  #2 Scan 権限（伝票を読む）: $(mark $s "ロールに dynamodb:Scan がない")"

  opt_headers=$(curl -s -D - -o /dev/null -X OPTIONS "$url/orders" \
    -H "Origin: https://example.com" -H "Access-Control-Request-Method: POST" \
    -H "Access-Control-Request-Headers: content-type")
  code=$(echo "$opt_headers" | head -1 | awk '{print $2}')
  if [ "$code" = 200 ] && echo "$opt_headers" | grep -qi "access-control-allow-origin"; then s=ok; else s=ng; fi
  echo "  #3 OPTIONS /orders (CORS): $(mark $s "HTTP $code")"

  count=$(aws dynamodb scan --table-name "$table" --select COUNT --query Count --output text)
  echo "  DynamoDB 内の伝票の件数  : $count"
done
