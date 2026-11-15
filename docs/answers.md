# 解答と解説

> ⚠️ イベント中は見ないでください！

コンソールの画面の表記は、AWS のアップデートで変わることがあります。ボタンが見つからなければ、似た名前のメニューを探してみてください。

---

## Challenge #1 メニューが表示されない！

### 原因

Lambda のコードが、存在しない変数 `MENU_ITEMS` を使っていました。正しくは `MENU` です。
Python が `NameError` で止まり、API Gateway は店員さんからまともな返事をもらえなかったので 502 を返していました。

### 調べ方

Lambda コンソールで関数 `aws-cafe-<環境ID>-order-function` を開き、「モニタリング」タブの「CloudWatch Logs を表示」からログに飛びます。いちばん新しいログストリームに、こんなログが残っています。

```
受付: GET /menu
[ERROR] NameError: name 'MENU_ITEMS' is not defined
Traceback (most recent call last):
  File "/var/task/index.py", line 34, in handler
    return response(200, {"menu": MENU_ITEMS})
```

エラーの種類も行番号も書いてあるので、ほぼ答えそのものです。

### 直し方

Lambda の「コード」タブで、`index.py` の該当行を直します。

```python
# 修正前
return response(200, {"menu": MENU_ITEMS})
# 修正後
return response(200, {"menu": MENU})
```

直したら「Deploy」ボタンを押します。エディタで書き換えただけでは本番のコードは変わらないので、ここを忘れると何も起きません。あとはアプリで Challenge #1 のクリア判定を押せば終わりです。

### 押さえておきたいこと

障害が起きたら、まずログを見る。今回の #1 はそれだけで解けるように作ってあります。そして Lambda は Deploy して初めて反映される、という点も覚えておいてください。

---

## Challenge #2 伝票が表示されない！

### 原因

Lambda の IAM ロールに、伝票を読む権限 `dynamodb:Scan` がありませんでした。伝票を書く `PutItem` の権限だけが残っていた状態です。

予約の伝票自体は DynamoDB にちゃんと入っていました。店員さん（Lambda）が伝票を読もうとして AWS に断られ、エラーで止まったので、API Gateway は 502 を返していました。

### 調べ方

まず DynamoDB コンソールでテーブル `aws-cafe-<環境ID>-orders` を開き、「項目を探索」を見ます。佐藤さん・鈴木さん・田中さんの予約伝票が3枚入っているはずです。「伝票はあるのに見えない」と分かれば、疑うのはデータではなく、読む側の店員さんです。

CloudWatch Logs には、次のようなログが出ています。

```
受付: GET /orders
[ERROR] ClientError: An error occurred (AccessDeniedException) when calling the Scan operation:
User: arn:aws:sts::<アカウントID>:assumed-role/aws-cafe-<環境ID>-order-function-role/aws-cafe-<環境ID>-order-function is not authorized to perform:
dynamodb:Scan on resource: arn:aws:dynamodb:ap-northeast-1:<アカウントID>:table/aws-cafe-<環境ID>-orders ...
Traceback (most recent call last):
  File "/var/task/index.py", line 38, in handler
```

長いですが、言っていることは「`aws-cafe-<環境ID>-order-function-role` というロールには、このテーブルへの `dynamodb:Scan` が許可されていない」です。

### 直し方

Lambda の「設定」→「アクセス権限」で実行ロール名のリンクを押し、IAM ロールを開きます。「許可」タブにあるインラインポリシー `OrdersTableAccess` を編集し、`Action` に `dynamodb:Scan` を足してください。`Resource` は変えません。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:<アカウントID>:table/aws-cafe-<環境ID>-orders"
    }
  ]
}
```

保存したらアプリの「伝票を更新」を押し、予約の伝票が出たらクリア判定を押します。

### 直したのにまだエラーが出るとき

ここは運営の検証でもハマりました。起動中の Lambda に IAM の変更が伝わるまで、検証では4〜5分ほどかかっています（2回測って、どちらも4分半前後）。Lambda は一度立ち上げた実行環境（店員さん）をしばらく使い回すので、権限を変えてもすぐには効かないことがあります。

待てないときは、Lambda の「設定」→「環境変数」→「編集」で、適当な変数（キー `RESTART`、値 `1` など）を追加して保存してください。設定が変わると実行環境が新しく作られ、新しい権限ですぐ動き出します。

### 押さえておきたいこと

`"Action": "dynamodb:*"` や `"Resource": "*"` にしても動きますし、そのほうが早く直ります。ただ、それは店員さんに金庫の鍵まで渡すようなものです。必要な操作を、必要なテーブルにだけ許可する。これが最小権限の考え方です。「書く」と「読む」が別の権限になっているのも、このためです。

「データがない」のか「データはあるのに読めない」のかを最初に切り分けると、原因にぐっと近づけます。IAM の変更はすぐ反映されるとは限らない、ということも頭の片隅に置いておくと、本番で慌てずに済みます。

---

## Challenge #3 お客様のスマホから注文できない！

### 原因

API Gateway のリソース `/orders` に、CORS のプリフライトに答える `OPTIONS` メソッドがありませんでした。

ブラウザは、別のサイト（オリジン）の API に `Content-Type: application/json` で `POST` するとき、先に `OPTIONS` で「送ってもいいですか？」と確認します。この確認に返事がなかったので、ブラウザが注文の送信を止めていました。

症状の違いは、次のように説明できます。

| 呼び出し方 | プリフライト | 結果 |
|---|---|---|
| `GET /menu`・`GET /orders`（単純リクエスト） | なし | 動く |
| `POST /orders`（JSON） | あり | 動かない |
| API Gateway のテスト機能や curl | ブラウザではないので CORS の確認自体をしない | 動く（＝「お店の端末では動く」） |

### 調べ方

ブラウザの開発者ツール（F12）の Console に、たとえばこんなエラーが出ます。文言はブラウザによって違います。

```
Access to fetch at 'https://xxxx.execute-api.ap-northeast-1.amazonaws.com/prod/orders' from origin '...'
has been blocked by CORS policy: Response to preflight request doesn't pass access control check: It does not have HTTP ok status.
```

Network タブを見ると、`orders` への `OPTIONS`（preflight）が 403 で返っています。API Gateway でリソース `/orders` を開くと、`GET` と `POST` はあるのに `OPTIONS` が見当たりません。

### 直し方

API Gateway コンソールで `aws-cafe-<環境ID>-api` を開き、リソース `/orders` を選んで「CORS を有効にする」を押します。設定はこの3点を確認すれば十分です。

- Access-Control-Allow-Methods で `GET`・`POST`（と `OPTIONS`）にチェックが入っている
- Access-Control-Allow-Headers に `Content-Type` が含まれている
- Access-Control-Allow-Origin が `*`

保存すると `/orders` に `OPTIONS` メソッドができます。

保存すると、緑の「CORS が正常に有効化されました」が出ます。ただ、画面上部の通知には前の操作の結果が残っていることがあるので、成功したかどうかは、ツリーの `/orders` の下に `OPTIONS` が増えたかで確かめてください。

最後に「API をデプロイ」でステージ `prod` を選んでデプロイしてください。これを忘れると、いくら設定してもお客様には届きません。数十秒待ってから、アプリでクリア判定を押します。

### 押さえておきたいこと

「curl やコンソールのテストでは動くのに、ブラウザだと動かない」なら、まず CORS を疑ってください。API Gateway（REST API）は、設定を変えたらデプロイが必要です。

ちなみに今回の Lambda は、レスポンスに `Access-Control-Allow-Origin: *` ヘッダーを最初から付けていました。Lambda プロキシ統合では、`GET` / `POST` の本体に付ける CORS ヘッダーは Lambda 側で返す必要があるためです。

---

## Challenge #4 開店！最初のお客様の注文を通せ！

アプリから「カフェラテ / M / 水野」で注文し、伝票に出ればクリアです。

#1〜#3 がすべて直っていれば、注文はこう流れます。

```
お客様アプリ ─(CORS プリフライト OPTIONS → OK)
            ─POST /orders→ API Gateway ─→ Lambda ─PutItem→ DynamoDB   … #3
お客様アプリ ←GET /orders── API Gateway ←─ Lambda ←─Scan─── DynamoDB   … #2
お客様アプリ ←GET /menu─── API Gateway ←─ Lambda                    … #1
```

## 今日直したもの

| 障害 | どこで起きた？ | ローカルでは問題なかった理由 | 何で気づけた？ | 教訓 |
|---|---|---|---|---|
| #1 | Lambda のコード | AWS に載せるときにコードを書き換えて、変数名を間違えた | CloudWatch Logs | まずログを見る。Deploy を忘れない |
| #2 | IAM ロール | ローカルには「権限」という考え方がなく、何でも読み書きできた | DynamoDB の中身と CloudWatch Logs | データがないのか、読めないのかを切り分ける。最小権限。IAM の反映には時間がかかることも |
| #3 | API Gateway の設定 | ローカルではアプリと API が同じ場所にあり、CORS が起きなかった | ブラウザの開発者ツール | ブラウザだけ動かないなら CORS。API はデプロイして反映 |

「ローカルでは動いたのに、クラウドに載せたら動かない」は、現場でもよくあります。権限、通信の経路（オリジン）、設定の反映といった、ローカルにはなかったものが原因になりがちです。

## 時間が余った人へ

- DynamoDB コンソールの「項目を探索」から伝票を1枚追加して、アプリの伝票欄に出るか試してみる
- 自分が注文した伝票が、DynamoDB にどんな形で保存されているか見てみる
- Lambda の「モニタリング」タブで、呼び出し回数やエラー数のグラフを眺めてみる
