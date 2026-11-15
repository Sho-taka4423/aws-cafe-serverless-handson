import json, os, uuid, datetime
import boto3

TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

MENU = [
    {"id": "latte", "name": "カフェラテ", "price": 480},
    {"id": "americano", "name": "アメリカーノ", "price": 420},
    {"id": "matcha", "name": "抹茶ラテ", "price": 520},
    {"id": "cocoa", "name": "ホットココア", "price": 450},
]

HEADERS = {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
}


def response(status, body):
    return {
        "statusCode": status,
        "headers": HEADERS,
        "body": json.dumps(body, ensure_ascii=False, default=str),
    }


def handler(event, context):
    method = event.get("httpMethod")
    path = event.get("resource")
    print(f"受付: {method} {path}")

    # メニューを返す
    if path == "/menu" and method == "GET":
        return response(200, {"menu": MENU_ITEMS})

    # 注文伝票の一覧を返す
    if path == "/orders" and method == "GET":
        items = TABLE.scan().get("Items", [])
        items.sort(key=lambda x: x.get("createdAt", ""))
        return response(200, {"orders": items})

    # 注文を受け付けて伝票を書く
    if path == "/orders" and method == "POST":
        try:
            body = json.loads(event.get("body") or "{}")
        except json.JSONDecodeError:
            return response(400, {"message": "注文内容が読めません"})
        if not body.get("item"):
            return response(400, {"message": "item は必須です"})
        order = {
            "orderId": str(uuid.uuid4())[:8],
            "item": body["item"],
            "size": body.get("size", "M"),
            "customer": body.get("customer", "お客様"),
            "createdAt": datetime.datetime.now(
                datetime.timezone(datetime.timedelta(hours=9))
            ).isoformat(timespec="seconds"),
        }
        TABLE.put_item(Item=order)
        print(f"注文を保存しました: {order}")
        return response(201, {"message": "注文完了！", "order": order})

    return response(404, {"message": "そのメニューはありません"})
