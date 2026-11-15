#!/usr/bin/env bash
# 共通関数（他のスクリプトから source して使う）
set -euo pipefail

# API Gateway の CreateDeployment などはスロットリングされやすいので、CLI の自動リトライを多めにする
export AWS_RETRY_MODE="${AWS_RETRY_MODE:-adaptive}"
export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

stack_name() { echo "aws-cafe-$1"; }

# スタック出力の値を取得: output <team> <OutputKey>
output() {
  aws cloudformation describe-stacks --stack-name "$(stack_name "$1")" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

orders_resource_id() {
  aws apigateway get-resources --rest-api-id "$1" \
    --query "items[?path=='/orders'].id" --output text
}

# ディレクトリ内の index.py を zip にする（CloudShell に zip コマンドが無くても動くよう python を使う）
zip_code() { # zip_code <index.pyのパス> <出力zip>
  python3 - "$1" "$2" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[2], "w", zipfile.ZIP_DEFLATED) as z:
    z.write(sys.argv[1], "index.py")
PY
}

update_code() { # update_code <関数名> <index.pyのパス>
  zip_code "$2" "$WORK_DIR/code.zip"
  aws lambda update-function-code --function-name "$1" \
    --zip-file "fileb://$WORK_DIR/code.zip" --output text --query LastUpdateStatus >/dev/null
  aws lambda wait function-updated-v2 --function-name "$1"
}

# 現在デプロイされている Lambda のコードを取得: current_code <関数名> <出力index.py>
current_code() {
  local url
  url=$(aws lambda get-function --function-name "$1" --query Code.Location --output text)
  curl -sSL -o "$WORK_DIR/current.zip" "$url"
  python3 - "$WORK_DIR/current.zip" "$2" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    open(sys.argv[2], "wb").write(z.read("index.py"))
PY
}

redeploy_api() { # redeploy_api <rest-api-id> <説明>
  local i
  for i in 1 2 3 4 5; do
    if aws apigateway create-deployment --rest-api-id "$1" --stage-name prod \
         --description "$2" --query id --output text >/dev/null; then
      return 0
    fi
    log "  API のデプロイが混み合っています。$((i * 10)) 秒後に再試行します"
    sleep $((i * 10))
  done
  return 1
}

role_policy() { # role_policy <ロール名> <テーブルARN> <アクション(カンマ区切り)>
  local actions
  actions=$(echo "$3" | sed 's/[^,]*/"&"/g')
  aws iam put-role-policy --role-name "$1" --policy-name OrdersTableAccess \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[$actions],\"Resource\":\"$2\"}]}"
}

table_arn() {
  aws dynamodb describe-table --table-name "$1" --query Table.TableArn --output text
}

log() { echo "[$(date +%H:%M:%S)] $*"; }
