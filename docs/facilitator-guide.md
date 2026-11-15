# 運営ガイド

得点・ランキング（スコアボード）は今回使いません。参考実装は [extras/scoreboard](../extras/scoreboard/README.md) に置いてあります。

## 全体の流れ

```
[事前] AWS からアカウント払い出し
   ↓
[事前] CloudShell でリポジトリを取得
   ↓
[事前] チームごとの環境をデプロイ → 障害を仕込む → 状態確認
   ↓
[事前] お客様アプリ・投影画面を公開し、チーム専用 URL を作る
   ↓
[当日] 参加者がログイン → 復旧 → クリア判定 → 開店成功！
   ↓
[事後] スタック削除
```

---

## 事前準備

### 0. 前提

リージョンは東京（ap-northeast-1）を想定しています。スクリプトは CloudShell（bash / AWS CLI v2 / python3 / curl）で動くように書いていて、手元の Mac でも動作を確認しました。

1 アカウントに複数チームを入れても、チームごとにアカウントを分けても使えます。スタック名が環境IDごとに分かれるので、ぶつかることはありません。

このガイドで「環境ID」と呼んでいるのは、`team01` のように運営が事前に割り当てる AWS 環境の名前です。AWS のリソース名とアプリの画面には、この環境IDが使われます。

実行するユーザーには、CloudFormation、IAM（名前付きロールの作成）、Lambda、API Gateway、DynamoDB、CloudWatch Logs の権限が要ります。

### 1. CloudShell でリポジトリを取得

AWS コンソール右上の CloudShell アイコンから起動し、リポジトリを取ってきます。

```bash
git clone https://github.com/Sho-taka4423/aws-cafe-serverless-handson.git
cd aws-cafe-serverless-handson
```

Git が使えなければ、GitHub のリポジトリページの「Code」→「Download ZIP」で zip を手に入れ、CloudShell の「アクション」→「ファイルのアップロード」で上げて展開してください。展開したフォルダ名は `aws-cafe-serverless-handson-main` になります。

### 2. チームごとの環境をデプロイして障害を仕込む

```bash
# 例: 10 チーム分（team01 〜 team10）
TEAMS=$(seq -f "team%02g" 1 10)

./scripts/deploy.sh $TEAMS            # 正常な環境を作る（並列でデプロイ、数分）
./scripts/break-environment.sh $TEAMS # 3つの障害を仕込む
sleep 30
./scripts/verify.sh $TEAMS            # 全チームが「❌ 障害あり」×3 になっていることを確認
```

`verify.sh` で、全チームがこうなっていれば準備完了です。

```
=== team01  https://xxxx.execute-api.ap-northeast-1.amazonaws.com/prod
  #1 GET /menu            : ❌ 障害あり (HTTP 502)
  #2 Scan 権限（伝票を読む）: ❌ 障害あり (ロールに dynamodb:Scan がない)
  #3 OPTIONS /orders (CORS): ❌ 障害あり (HTTP 403)
  DynamoDB 内の伝票の件数  : 3
```

`#3` が「✅ 正常」のままなら、API の反映がまだ終わっていないだけです。30 秒ほど待ってから `verify.sh` をもう一度実行してください。

仕込む障害の中身は次のとおりです。

| # | 内容 | 仕込み方 |
|---|---|---|
| 1 | Lambda コードで未定義変数 `MENU_ITEMS` を参照 → `/menu` が 502 | `lambda/broken/index.py` をアップロード |
| 2 | 予約伝票を 3 枚入れたうえで、IAM ロールのインラインポリシー `OrdersTableAccess` から `dynamodb:Scan`（読む権限）を削除 → `/orders` の GET が 502 | `put-item` で予約伝票を投入、`put-role-policy` で上書き |
| 3 | `/orders` の `OPTIONS` メソッドを削除し、`prod` ステージに再デプロイ | `delete-method` → `create-deployment` |

`break-environment.sh` は伝票（DynamoDB の項目）をいったん空にして、開店前の予約伝票を3枚（佐藤・鈴木・田中）入れ直します。リハーサルで直したあとも、もう一度実行すれば当日用の状態に戻せます。

### 3. お客様アプリ・投影画面の公開先

お客様アプリと投影画面は、GitHub Pages で公開済みです。運営が置き場所を用意する必要はありません。

| 画面 | URL |
|---|---|
| お客様アプリ | https://sho-taka4423.github.io/aws-cafe-serverless-handson/app/index.html |
| ローカル版 | https://sho-taka4423.github.io/aws-cafe-serverless-handson/app/index.html?local=1 |
| カウントダウン | https://sho-taka4423.github.io/aws-cafe-serverless-handson/ops/countdown.html?min=70 |

GitHub Pages は `main` ブランチの内容をそのまま公開しています。リポジトリに push すると、数分で公開中の画面にも反映されます。

別の場所（S3 の静的ウェブサイトホスティングや Amplify Hosting など）に置きたい場合は、`app/index.html` をそのまま置けば動きます。1 ファイルで完結した静的 HTML です。どこに置く場合も、アプリと API は別オリジンにしてください。同じオリジンだと CORS が起きず、#3 の学びがなくなるためです。GitHub Pages も含め、ふつうに置けば自然に別オリジンになります。

### 4. チーム専用 URL を作る

環境IDと API URL が入った状態で開ける URL を、環境ごとに出力します。アプリには設定欄がないので、参加者はこの URL で開くだけで始められます。

```bash
./scripts/print-urls.sh https://sho-taka4423.github.io/aws-cafe-serverless-handson/app/index.html $TEAMS
```

出力はスプレッドシートなどにまとめ、ログイン情報と一緒に配ってください。

### 5. リハーサル（推奨）

1 チーム分を使い、手順書どおりに直せるかを通しで試しておくと安心です。

```bash
./scripts/fix-environment.sh team01        # 全部直す
./scripts/verify.sh team01                 # ✅ ×3 を確認
# アプリで #1〜#4 のクリア判定 → 開店成功画面を確認
./scripts/break-environment.sh team01      # 当日用に壊し直す
```

アプリのクリア状態とヒントは、ブラウザに保存されています。リハーサルのあとは、チーム専用 URL の末尾に `&reset=1` を付けて一度開くと消せます。

---

## 当日の進行（全体 120 分 / ハンズオン約 100 分）

| 時間 | 内容 | 画面 |
|---|---|---|
| 0:00–0:10 | オープニング、ストーリー紹介。まずローカル版で「本来はこう動くお店」を見せてから、「これを AWS に載せたら動かなくなった」と店長の悲鳴につなげると盛り上がる | `app/index.html?local=1` |
| 0:10–0:20 | お店に例えたサービス解説（[00](00-story-and-architecture.md)）、ログインとアプリを開く（[01](01-getting-started.md)） | スライド |
| 0:20–1:30 | チャレンジタイム（70 分） | `countdown.html?min=70` |
| 1:30–1:45 | 答え合わせ（[解答と解説](answers.md)） | スライド / コンソール実演 |
| 1:45–1:55 | ふりかえり（開店成功したチームの紹介、詰まったところの共有など） | |
| 1:55–2:00 | 片付けの案内、アンケート | |

### カウントダウン画面

`ops/countdown.html?min=70`（https://sho-taka4423.github.io/aws-cafe-serverless-handson/ops/countdown.html?min=70）を開くと、すぐにカウントダウンが始まります。画面の下にマウスを乗せると操作ボタンが出て、一時停止や 5 分延長ができます。残り 5 分で数字が赤く点滅し、0 になると「開店！🎉」に変わります。

### 進行のコツ

15 分たっても #1 で止まっているチームが多いようなら、全体に「まずログを見てみよう」と声をかけてください。

#2 は、IAM を正しく直しても数分はエラーが続くことがあります。詳しくは下のトラブル表に書きました。運営の検証でもここで一度ハマったので、開始前に「直したのにエラーが続くときはヒント3を見てね」と伝えておくと混乱が減ります。

#3 の CORS はいちばん難しいチャレンジです。原因がログに出ないので、開発者ツールを開くという発想がないと手が止まります。手順書に開き方は書いてありますが、止まっているチームには「ブラウザの中を見てみよう」と声をかけてください。CORS を有効にしたあとの「API のデプロイ」忘れでも詰まりやすいはずです。

---

## 想定トラブルと対処

| 症状 | 原因と対処 |
|---|---|
| #2 で IAM を正しく直したのに、数分間 AccessDenied が続く | 起動中の Lambda 実行環境に新しい権限が届くまで、検証では約 4〜5 分かかった（3回測って、いずれも4分半前後）。待つか、Lambda の環境変数を 1 つ追加して保存すればすぐ反映される。運営が直すなら `./scripts/fix-environment.sh <チーム> 2`（実行環境の作り直しまで自動でやる） |
| #3 で CORS を有効にしたら「2 メソッドの CORS ヘッダーを更新できませんでした」と赤いエラーが出た | 今のテンプレートでは出ない。`GET` / `POST` に 200 のメソッドレスポンスと統合レスポンスを定義して対策済み（2026-11-15 に検証）。出た場合は対策前のテンプレートで作った環境なので、`/orders` の下に `OPTIONS` ができていれば問題なし。そのまま「API をデプロイ」へ進んでもらう |
| #3 で「デプロイできた」と思ったのに直っていない | 画面上部の通知は前の操作の結果が残っていることがある。ステージ `prod` のデプロイ履歴か、`/orders` の下の `OPTIONS` を見て確かめる |
| #3 で CORS を有効にしたのに直らない | 「API をデプロイ」をしていないか、デプロイ直後でまだ反映されていない。反映には数十秒かかる。ステージが `prod` かも見る |
| #1 でコードを直したのに直らない | 「Deploy」を押していない |
| #2 で `Resource` を `*` や `dynamodb:*` にして直した | 動くのでクリアでよい。答え合わせで最小権限の話をする |
| アプリに「お店の URL が指定されていません」と出る / 別の環境につながっている | チーム専用 URL をまるごと開き直す。URL を開くたびに接続先が上書きされる |
| 前の人のクリア状態やヒントが残っている | チーム専用 URL の末尾に `&reset=1` を付けて開く |
| どうしても進めないチームがいる | `./scripts/fix-environment.sh <チーム> 1`（2 / 3）で、そのチャレンジだけ直せる |
| 環境ごと壊してしまった | まず `./scripts/fix-environment.sh <チーム>` を試す。だめなら `aws cloudformation delete-stack --stack-name aws-cafe-<チーム>` でスタックを消し、削除が終わってから `deploy.sh` → `break-environment.sh` で作り直す。テンプレートが同じだと、`deploy.sh` を再実行しただけでは手で変えた部分は元に戻らないので注意 |
| `break-environment.sh` が TooManyRequests で失敗した | API Gateway のデプロイ API のレート制限に当たっている。スクリプトは自動で再試行するが、それでも失敗したチームだけ再実行すればよい |

---

## 片付け

イベントが終わったら、作ったスタックを消します。

```bash
TEAMS=$(seq -f "team%02g" 1 10)
for t in $TEAMS; do aws cloudformation delete-stack --stack-name aws-cafe-$t; done
```

DynamoDB テーブルとロググループもスタックと一緒に消えます。参加者がコンソールで足した `OPTIONS` メソッドなども、API ごと消えるので個別に掃除する必要はありません。

AWS から払い出されたアカウントの後片付けは、払い出し元の案内に従ってください。
