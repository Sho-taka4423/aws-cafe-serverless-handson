# スコアボード（他企画用の参考実装）

AWS Cafe ハンズオンでは使っていません。得点やランキングのあるイベントをやるときに流用できるよう、残してあります。

2026-11-14 に AWS へ実際にデプロイし、AWS Cafe のアプリから送ったクリアがランキングに反映されることを確認しました。確認に使ったスタックは削除済みです。ただしそのあと、ロググループをテンプレートで管理するよう手を入れています。この版は lint しか通していないので、使う前に一度デプロイして試してください。

## 構成

```
参加者のアプリ ──POST /progress──▶ API Gateway (HTTP API) ─▶ Lambda ─▶ DynamoDB
投影画面       ──GET /leaderboard─▶        〃               ─▶   〃   ─▶    〃
```

| ファイル | 内容 |
|---|---|
| `scoreboard.yaml` | CloudFormation テンプレート（HTTP API + Lambda(Python) + DynamoDB + ロググループ） |
| `scoreboard.html` | ランキング投影画面（「本日のヒーロー」。5 秒ごとに自動更新、上位 3 チームを表彰台表示） |

## しくみ

### 1. クリアの記録

参加者側のアプリがチャレンジのクリアを判定したら、このリクエストを送ります。

```
POST /progress
{ "team": "team01", "challenge": 2, "hints": 1 }
```

Lambda は DynamoDB に「チーム（パーティションキー）× チャレンジ（ソートキー）」で 1 件保存し、クリア時刻 `clearedAt` をサーバー側で付けます。

保存には `ConditionExpression: attribute_not_exists(team)` を付けていて、記録されるのは最初の 1 回だけです。同じクリアを何度送っても上書きされないので、クリア時刻も順位も動きません。`hints` はクリア判定を押した時点のヒント使用回数で、0〜10 の範囲に丸めています。

### 2. 集計

合計点はどこにも保存していません。`GET /leaderboard` が呼ばれるたびに全件を Scan し、その場で計算します。

```
チャレンジ 1 件の点数 = 基本点 + 早解きボーナス − ヒント回数 × 50
チームの合計         = クリアしたチャレンジの点数の合計
並び順               = 合計点の高い順。同点なら最後のクリア時刻が早い順
```

| 項目 | 既定値 | テンプレート内の定数 |
|---|---|---|
| 基本点 | #1: 100 / #2: 150 / #3: 150 / #4: 200 | `POINTS` |
| 早解きボーナス | 各チャレンジのクリア時刻順で 1〜3 番目に +50 / +30 / +10 | `BONUS` |
| ヒント減点 | 1 回 −50 | `HINT_PENALTY` |

たとえば 4 つともヒントなしで、すべて 2 番目にクリアしたチームは 600 + 30 × 4 = 720 点になります。

レスポンスはこんな形です。

```json
{"teams": [{"team": "team01", "score": 750, "cleared": [1, 2, 3, 4], "hints": 1, "lastClearedAt": "2026-11-14T12:52:19.236+00:00"}]}
```

## 使い方

### デプロイ

```bash
aws cloudformation deploy \
  --template-file extras/scoreboard/scoreboard.yaml \
  --stack-name aws-cafe-scoreboard \
  --capabilities CAPABILITY_IAM

aws cloudformation describe-stacks --stack-name aws-cafe-scoreboard \
  --query "Stacks[0].Outputs[?OutputKey=='ScoreboardApiUrl'].OutputValue" --output text
```

### AWS Cafe のアプリと連携する

お客様アプリ（`app/index.html`）には送信処理を残してあります。URL に `sb` を付けたときだけ動きます。

```
https://<アプリの公開先>/index.html?env=team01&api=<お店のAPI URL>&sb=<スコアボードAPI URL>
```

スコアボードには、チーム名として環境ID（`env` の値、例: `team01`）が送られます。

`print-urls.sh` を環境変数 `SB_URL` 付きで実行すれば、`sb` 入りの URL をまとめて出せます。

```bash
SB_URL=<スコアボードAPI URL> ./scripts/print-urls.sh <アプリURL> team01 ...
```

今のアプリは得点を表示しません。参加者にも点数を見せたいなら、アプリ側に表示を足してください。

### 投影

```
extras/scoreboard/scoreboard.html?api=<スコアボードAPI URL>
```

API 側で CORS を許可しているので、ローカルでファイルを開くだけで動きます。

### リセットと片付け

リハーサルで入ったスコアは、DynamoDB コンソールでスコアテーブルの項目を消せばリセットできます。使い終わったら `aws cloudformation delete-stack --stack-name aws-cafe-scoreboard` でスタックごと消してください。

## 他の企画に流用するとき

チャレンジ数や点数を変えるだけなら、`POINTS` を書き換えれば済みます。`challenge` が `POINTS` のキーにないリクエストは 400 で弾かれます。

一番気をつけたいのは、不正対策をしていないことです。誰でも API を叩けばクリアを記録できてしまいます。景品を出すなら、次のどれかを足すことを検討してください。

- サーバー側でクリア条件を検証する（AWS Cafe なら、各チームの API を実際に叩いて確かめる）
- チームごとにトークンを配り、送信時に照合する
- 表彰の前に、運営が実際の状態を確認する

ステージには `ThrottlingBurstLimit: 50` / `ThrottlingRateLimit: 20` を設定しています。参加人数が多いイベントでは見直してください。

ランキングは毎回 Scan で集計しています。数十〜数百件のイベント規模なら問題ありませんが、大きく広げるなら集計結果を別に持つ形にしたほうがよいです。
