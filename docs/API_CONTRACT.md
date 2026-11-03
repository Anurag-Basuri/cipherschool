# QuickKart API Contract (v1)

The backend is simulated in-process by `lib/mock_server/` and reached through
`ApiClient` → `Transport`. It behaves like a real HTTP JSON API.

## Conventions

- JSON bodies. Money in **requests and order responses is integer paise**.
  Product prices in catalog responses are **rupee decimals** (legacy).
- Errors: `{"error": "MACHINE_CODE", "message": "Human text", "details": ...}`.
- `5xx` and timeouts can happen at any time (see Dev tools). A timeout does
  **not** mean the server didn't process the request.

## Catalog

### `GET /v1/categories`
`200 → [{ "id": "dairy", "name": "Dairy, Bread & Eggs", "emoji": "🥛" }]`

### `GET /v1/products?category=&cursor=&limit=&deals=`
- `category` optional; omit for all products.
- `limit` 1–30, default 10.
- `cursor` opaque; use `nextCursor` from the previous page.
- `deals=true` returns only discounted, in-stock products.

```json
200 {
  "items": [{
    "id": "dairy-03",
    "name": "Farm Eggs",
    "categoryId": "dairy",
    "emoji": "🥚",
    "unit": "6 pcs",
    "price": 54.0,       // rupees
    "mrp": 60.0,         // rupees
    "stock": 45,
    "maxPerOrder": 4
  }],
  "nextCursor": "bzoxMA=="   // null on the last page
}
```
`400 INVALID_CURSOR`

### `GET /v1/products/search?q=`
`200 → {"query": "...", "items": [Product]}` (max 20)
`400 QUERY_TOO_SHORT` when `q` has fewer than 2 characters.

### `POST /v1/products/batch`
Latest data for specific products, e.g. for cart reconciliation.
```json
{ "ids": ["dairy-03", "snacks-01"] }      // max 50
200 { "items": [Product], "missing": ["snacks-01"] }
```
`missing` = unknown or discontinued products.

## Coupons

### `POST /v1/coupons/validate`
```json
{ "code": "SAVE10" }
200 {
  "code": "SAVE10", "type": "percent", "value": 10,
  "maxDiscountPaise": 7500, "minOrderPaise": 19900,
  "expiresAt": "2026-12-01T10:00:00.000Z",
  "description": "10% off up to ₹75, min ₹199"
}
```
`type` is `flat` (value in paise) or `percent` (value in %).
`404 COUPON_NOT_FOUND`, `409 COUPON_EXPIRED`.
The minimum order is **not** checked here; it is checked when ordering.

## Orders

### `POST /v1/orders`
Headers: `Idempotency-Key: <unique string>` (optional but **strongly
recommended**). If the same key is sent again with the **same body**, the
server returns the order created the first time (`200`) instead of creating
a new one. The same key with a different body → `422 IDEMPOTENCY_KEY_REUSED`.

```json
{
  "items": [{ "productId": "dairy-03", "quantity": 2, "unitPricePaise": 5400 }],
  "couponCode": null,             // or e.g. "SAVE10"
  "expectedTotalPaise": 13300
}
```
`201 → Order`

| Status | `error` | `details` |
|---|---|---|
| 400 | `EMPTY_CART`, `INVALID_REQUEST` | |
| 409 | `PRODUCT_UNAVAILABLE` | `[{productId}]` |
| 409 | `PRICE_CHANGED` | `[{productId, expectedPricePaise, currentPricePaise}]` |
| 422 | `QUANTITY_LIMIT` | `[{productId, requested, maxPerOrder}]` |
| 409 | `INSUFFICIENT_STOCK` | `[{productId, requested, available}]` |
| 409 | `COUPON_INVALID` | `{code, reason: NOT_FOUND / EXPIRED / MIN_ORDER_NOT_MET}` |
| 409 | `TOTAL_MISMATCH` | `{expectedTotalPaise, serverTotalPaise, subtotalPaise, discountPaise, deliveryFeePaise}` |
| 422 | `IDEMPOTENCY_KEY_REUSED` | |
| 503 | `STORE_CLOSED` | |

Checks run in the order of the table; the first failing check is returned.

### Order
```json
{
  "id": "QK-1001",
  "status": "placed",      // placed | packed | out_for_delivery | delivered
  "createdAt": "2026-11-03T10:00:00.000Z",
  "items": [{ "productId": "...", "name": "...", "emoji": "🥚",
              "quantity": 2, "unitPricePaise": 5400 }],
  "subtotalPaise": 10800, "discountPaise": 0,
  "deliveryFeePaise": 2500, "totalPaise": 13300,
  "couponCode": null
}
```

### `GET /v1/orders` → `{"items": [Order]}` (newest first)
### `GET /v1/orders/{id}` → `Order` | `404 ORDER_NOT_FOUND`

## Remote config

### `GET /v1/config`
`200 → {"version": 3, "values": { "store_open": true, ... }}`
See BUSINESS_RULES.md §7 for keys.

## Realtime (no HTTP; Dart streams on `MockServer`)

| Stream | Behaves like |
|---|---|
| `configUpdates` → `Stream<int>` (new version) | Firebase Remote Config `onConfigUpdated` |
| `watchOrder(id)` → `Stream<Map>` (Order JSON) | Firestore document snapshot listener |
| `pushMessages` → `Stream<Map>` `{title, body, data: {type, orderId, status}}` | `FirebaseMessaging.onMessage` |

Reach them through the existing repositories (`ConfigRepository.remoteUpdates`,
`OrderTrackingRepository.watchOrderDocument` / `pushMessages`) rather than
the server directly.
