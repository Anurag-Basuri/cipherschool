# QuickKart Business Rules

How QuickKart works as a business. Where the app and this document disagree,
this document is right.

## 1. Prices

- Every product has a selling price and an MRP. When the MRP is higher than
  the price, the product is shown with a discount ("20% OFF").
- Prices are shown in rupees, with paise only when there are any:
  ₹50, ₹49.99.
- The customer pays exactly the prices shown in the catalog at the time of
  ordering.

## 2. Delivery fee

- Orders of ₹199 or more get free delivery. Smaller orders pay a ₹25
  delivery fee.
- The order value for this rule is the amount **after** any coupon discount.
- Both amounts are set by the business and can change at any time.
- An empty cart costs nothing.

## 3. Coupons

| Type | Benefit |
|---|---|
| Flat | A fixed amount off, never more than the cart value |
| Percent | A percentage of the cart value (rounded down to the paisa), up to a maximum discount |

- Each coupon has a minimum cart value and an expiry date.
- If the cart is below the minimum, the coupon stays applied but gives no
  discount until the minimum is reached. The customer can still place the
  order.
- Expired or unknown coupons cannot be used.

## 4. Cart

- A customer's cart is kept on their phone, including when the app is
  closed.
- A customer can buy up to the per-order limit of a product, and never more
  than is in stock.

## 5. Checkout and orders

- Customers only pay amounts they have agreed to. If the cart has changed
  since they last saw it:
  - a lower price can be applied without asking;
  - a higher price, a lower available quantity, an item that is out of
    stock or no longer sold, or a coupon that no longer works must be shown
    to the customer, who confirms before ordering.
- Out-of-stock and discontinued items are never ordered.
- Placing an order once results in exactly one order.
- After a successful order, the cart is empty.

## 6. Catalog

- Products are listed in the order chosen by our merchandising team.
- Customers can browse by category or see all products, and can search by
  name.
- Customers on a poor connection should still be able to browse what they
  have already seen.

## 7. Running the store remotely

The operations team controls these settings from the config console. Changes
take effect for customers without an app update.

| Setting | Meaning |
|---|---|
| `min_supported_version` | Customers on an older app version must update before they can continue. |
| `latest_version` | Customers on an older version are invited to update, and may decline. |
| `update_url` | Where customers go to update. |
| `store_open` | When `false`, customers can browse but cannot order. |
| `store_closed_message` | The message shown while the store is closed. |
| `home_banner` | Promotional banner: `{title, subtitle, color}`. |
| `home_sections` | Which home screen sections to show, in order: `banner`, `categories`, `deals`, `all_products`. |
| `delivery_fee_paise` | Delivery fee (2500 = ₹25). |
| `free_delivery_threshold_paise` | Order value for free delivery (19900 = ₹199). |

A mistake in the console must never stop customers from using the app.
