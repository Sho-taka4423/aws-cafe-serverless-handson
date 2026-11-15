#!/usr/bin/env bash
# 正常な AWS Cafe 環境をチームごとにデプロイする
#   使い方: ./scripts/deploy.sh team01 [team02 ...]
#   10チーム分: ./scripts/deploy.sh $(seq -f "team%02g" 1 10)
source "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || { echo "使い方: $0 <環境ID> [環境ID ...]"; exit 1; }

pids=()
for team in "$@"; do
  log "$team: デプロイ開始 ($(stack_name "$team"))"
  aws cloudformation deploy \
    --template-file "$REPO_DIR/cfn/aws-cafe.yaml" \
    --stack-name "$(stack_name "$team")" \
    --parameter-overrides "TeamName=$team" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset >/dev/null &
  pids+=($!)
done

fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
[ $fail -eq 0 ] || { log "デプロイに失敗したスタックがあります。CloudFormation コンソールでイベントを確認してください"; exit 1; }

echo
log "デプロイ完了。各チームの API URL:"
for team in "$@"; do
  printf "  %-10s %s\n" "$team" "$(output "$team" ApiUrl)"
done
