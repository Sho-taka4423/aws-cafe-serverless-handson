#!/usr/bin/env bash
# 障害を直す（解答・リハーサル・詰まった参加者の救済用）
#   使い方: ./scripts/fix-environment.sh <環境ID> [1|2|3|all]   （省略時 all）
#   参加者がコンソールで行う操作と同じ内容を CLI で実行する
source "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || { echo "使い方: $0 <環境ID> [1|2|3|all]"; exit 1; }
team=$1; target=${2:-all}

fn=$(output "$team" FunctionName)
role=$(output "$team" RoleName)
table=$(output "$team" TableName)
api=$(output "$team" RestApiId)

fix1() {
  log "$team: #1 コードの MENU_ITEMS を MENU に直してデプロイ"
  current_code "$fn" "$WORK_DIR/index.py"
  sed -i.bak 's/"menu": MENU_ITEMS}/"menu": MENU}/' "$WORK_DIR/index.py"
  update_code "$fn" "$WORK_DIR/index.py"
}
fix_iam() {
  log "$team: #2 IAM ロールに dynamodb:Scan を追加（対象は注文テーブルのみ）"
  role_policy "$role" "$(table_arn "$table")" "dynamodb:Scan,dynamodb:PutItem"
  # 起動済みの Lambda 実行環境には権限の変更がすぐ反映されないことがある（検証では約4〜5分）。
  # 環境変数を更新して実行環境を作り直し、すぐに反映させる
  log "$team: #2 Lambda の実行環境を作り直す（環境変数 RESTARTED_AT を更新）"
  vars=$(aws lambda get-function-configuration --function-name "$fn" --query Environment.Variables --output json |
    python3 -c 'import sys,json,time; v=json.load(sys.stdin) or {}; v["RESTARTED_AT"]=str(int(time.time())); print(json.dumps({"Variables":v}))')
  aws lambda update-function-configuration --function-name "$fn" --environment "$vars" \
    --query LastUpdateStatus --output text >/dev/null
  aws lambda wait function-updated-v2 --function-name "$fn"
}
fix_cors() {
  log "$team: #3 /orders に OPTIONS（CORS）を追加して API をデプロイ"
  rid=$(orders_resource_id "$api")
  aws apigateway delete-method --rest-api-id "$api" --resource-id "$rid" --http-method OPTIONS 2>/dev/null || true
  aws apigateway put-method --rest-api-id "$api" --resource-id "$rid" --http-method OPTIONS \
    --authorization-type NONE >/dev/null
  aws apigateway put-integration --rest-api-id "$api" --resource-id "$rid" --http-method OPTIONS \
    --type MOCK --request-templates '{"application/json":"{\"statusCode\": 200}"}' >/dev/null
  aws apigateway put-method-response --rest-api-id "$api" --resource-id "$rid" --http-method OPTIONS \
    --status-code 200 --response-parameters \
    '{"method.response.header.Access-Control-Allow-Headers":true,"method.response.header.Access-Control-Allow-Methods":true,"method.response.header.Access-Control-Allow-Origin":true}' >/dev/null
  aws apigateway put-integration-response --rest-api-id "$api" --resource-id "$rid" --http-method OPTIONS \
    --status-code 200 --response-parameters \
    '{"method.response.header.Access-Control-Allow-Headers":"'"'"'Content-Type'"'"'","method.response.header.Access-Control-Allow-Methods":"'"'"'GET,POST,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}' >/dev/null
  redeploy_api "$api" "fix CORS"
}

case "$target" in
  1) fix1 ;; 2) fix_iam ;; 3) fix_cors ;;
  all) fix1; fix_iam; fix_cors ;;
  *) echo "1 / 2 / 3 / all のどれかを指定してください"; exit 1 ;;
esac
log "$team: 完了（API の変更は反映まで数十秒かかることがあります）"
