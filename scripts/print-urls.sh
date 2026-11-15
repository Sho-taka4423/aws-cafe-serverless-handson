#!/usr/bin/env bash
# 参加者に配る「チーム専用アプリ URL」を一覧表示する（環境IDと API URL が入力済みの状態で開ける）
# アプリには設定欄がないので、参加者はこの URL を開くだけで始められる
#   使い方: ./scripts/print-urls.sh <アプリの公開URL> team01 [team02 ...]
#   例:     ./scripts/print-urls.sh https://example.com/app/index.html team01 team02
#   スコアボード連携（任意・extras/scoreboard）を使う場合は SB_URL を指定する:
#           SB_URL=https://xxxx.execute-api.ap-northeast-1.amazonaws.com ./scripts/print-urls.sh <アプリURL> team01
source "$(dirname "$0")/lib.sh"
[ $# -ge 2 ] || { echo "使い方: $0 <アプリURL> <環境ID> [環境ID ...]"; exit 1; }
app=$1; shift
enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
sb_param=""
[ -n "${SB_URL:-}" ] && sb_param="&sb=$(enc "$SB_URL")"
printf "%s\t%s\n" "環境ID" "アプリURL"
for team in "$@"; do
  api=$(output "$team" ApiUrl)
  printf "%s\t%s?env=%s&api=%s%s\n" "$team" "$app" "$(enc "$team")" "$(enc "$api")" "$sb_param"
done
