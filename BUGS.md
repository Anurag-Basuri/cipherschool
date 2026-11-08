# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Cart mutations not persisted after restart (QK-101)

- **Symptom:** Items removed or decremented in the cart come back after closing and reopening the app. Removed coupons also reappear.
- **Steps to reproduce:**
  1. Add 2 units of Milk and 1 Chips to cart, and apply coupon SAVE10.
  2. Reduce Milk to 1 unit, remove Chips, and remove the coupon.
  3. Close and reopen the app (or restart app state from storage). Milk is back to 2, Chips is back, and SAVE10 is still applied.
- **Root cause:** `lib/features/cart/application/cart_controller.dart` in `decrement()`, `remove()`, and `removeCoupon()`. These methods updated local in-memory `state` but never called `_storage.save()`.
- **Fix:** Introduced a central `_commit(Cart updated)` method that saves to `CartStorage` on every mutation (`decrement`, `remove`, `removeCoupon`, `applyCoupon`, `add`, `increment`).
- **Test:** `test/cart_persistence_test.dart` → `a reduced quantity survives a restart`, `a line decremented to zero stays gone after a restart`, `a removed line stays gone after a restart`, `a removed coupon stays removed after a restart`
- **Commits:** test `f61eda0` → fix `e6359de`

---

## BUG-2: Stale GET cache blocks price updates, orders, and config (QK-102)

- **Symptom:** Price changes on the server are not reflected when pulling to refresh. Placing an order does not show up in the "My orders" screen until restarting the app. Remote config updates do not take effect.
- **Steps to reproduce:**
  1. Browse catalog and observe item price (e.g. ₹54).
  2. Update price on the backend. Pull down to refresh catalog. Old price ₹54 is still displayed.
  3. Place an order and navigate to "My orders". The newly placed order is missing.
- **Root cause:** `lib/core/network/api_client.dart` had a 10-minute in-memory response cache that was always returned before reaching the transport. Additionally, `ordersProvider` in `lib/features/orders/data/order_tracking_repository.dart` was never invalidated upon checkout completion in `checkout_controller.dart`.
- **Fix:** Added `bypassCache: true` parameter to `ApiClient.get()`. Wired `bypassCache: true` into pull-to-refresh (`CatalogController.refresh`), order fetching (`OrderApi.getOrders`), and config reloading (`ConfigRepository.load`). Invalidated `ordersProvider` upon successful order placement.
- **Test:** `test/stale_cache_test.dart` → `pull to refresh fetches updated prices instead of cached ones`, `ordersProvider updates after order is placed`, `ConfigRepository.load fetches fresh config after update`, `ApiClient does not retry non-transient 4xx errors`
- **Commits:** test `99069bd` → fix `ea13582`

---

## BUG-3: Lost increments on rapid cart button taps

- **Symptom:** Fast double-tapping the "+" button on a product adds only 1 unit instead of 2.
- **Steps to reproduce:**
  1. Add an item with quantity 1.
  2. Tap "+" rapidly twice.
  3. Cart badge and quantity show 2 instead of 3.
- **Root cause:** `lib/features/cart/application/cart_controller.dart` in `increment()` and `add()`. The controller read `state`, awaited the asynchronous disk write `_storage.save(updated)`, and only then published `state = updated`. A second tap arriving while disk I/O was in flight read the stale in-memory state and overwrote the first tap.
- **Fix:** Published `state = updated` synchronously before awaiting `_storage.save(updated)` in `_commit()`.
- **Test:** `test/cart_rapid_taps_test.dart` → `two rapid increments add two units`, `rapid "+" then "-" ends at the right quantity`
- **Commits:** test `49cab8d` → fix `2a9e543`

---

## BUG-4: Delivery fee charged at exact free-delivery threshold

- **Symptom:** An order of exactly ₹199 is wrongly charged a ₹25 delivery fee instead of getting free delivery.
- **Steps to reproduce:**
  1. Add items totaling exactly ₹199.00 (19900 paise) to the cart.
  2. Inspect the bill breakdown. Delivery fee shows ₹25 and To Pay shows ₹224.
- **Root cause:** `lib/features/cart/domain/cart_pricing.dart` line 43: `payable > threshold` checked strict inequality (`>`), violating `BUSINESS_RULES.md` §2 which specifies free delivery for orders of "₹199 or more".
- **Fix:** Changed the comparison from `payable > threshold` to `payable >= threshold`.
- **Test:** `test/delivery_fee_test.dart` → `an order of exactly the threshold gets free delivery`
- **Commits:** test `157a2f3` → fix `3f5213e`

---

## BUG-5: formatMoney truncates paise

- **Symptom:** Product prices with paise like ₹49.99 are displayed as ₹49.
- **Steps to reproduce:**
  1. View a product priced at ₹49.99 (4999 paise).
  2. The UI formats the price as ₹49, hiding the 99 paise.
- **Root cause:** `lib/core/utils/money.dart` line 9: `paise ~/ 100` did integer division and completely dropped the fractional paise remainder.
- **Fix:** Updated `formatMoney` to inspect `abs % 100` and append zero-padded `.XX` whenever remainder is non-zero (matching `BUSINESS_RULES.md` §1).
- **Test:** `test/format_money_test.dart` → `paise are shown when present`, `single-digit paise are zero padded`
- **Commits:** test `40fed10` → fix `44b89a6`

---

## BUG-6: rupeesToPaise loses a paisa due to floating-point truncation

- **Symptom:** A price of 19.99 from the catalog API becomes 1998 paise instead of 1999 paise.
- **Steps to reproduce:**
  1. API returns a catalog product with price `19.99`.
  2. `ProductDto.fromJson` converts price to paise.
  3. Price is recorded as 1998 paise (₹19.98).
- **Root cause:** `lib/core/utils/money.dart` line 14: `(rupees * 100).toInt()`. Floating-point multiplication `19.99 * 100` yields `1998.9999999999998`, and `.toInt()` truncates toward zero.
- **Fix:** Replaced `.toInt()` with `.round()`.
- **Test:** `test/rupees_to_paise_test.dart` → `converts rupee doubles to exact paise`, `ProductDto maps a fractional API price without losing a paisa`
- **Commits:** test `efd2330` → fix `53bdf9d`

---

## BUG-7: CategoryScreen listener leak and setState after dispose

- **Symptom:** App throws unhandled exceptions (`setState() called after dispose()`) when remote config updates are broadcast after navigating away from a category screen.
- **Steps to reproduce:**
  1. Open a category screen (e.g. Dairy).
  2. Press back to return to the home screen.
  3. Publish a config update (e.g. sales banner or delivery fee change).
  4. Crash occurs with `FlutterError: setState() called after dispose()`.
- **Root cause:** `lib/features/catalog/presentation/category_screen.dart` in `initState()` subscribed to `configRepository.remoteUpdates.listen(...)` without storing the `StreamSubscription` or cancelling it in `dispose()`.
- **Fix:** Stored `_configSubscription`, cancelled it inside `dispose()`, and added `if (!mounted) return;` guard before `setState()`.
- **Test:** `test/category_screen_leak_test.dart` → `CategoryScreen does not call setState after dispose on config update`
- **Commits:** test `f41e16b` → fix `f9822b4`

---

## BUG-8: Catalog offline cache key lacks categoryId

- **Symptom:** When offline, browsing one category displays products from an entirely different category that was viewed earlier.
- **Steps to reproduce:**
  1. View category "Dairy" while online.
  2. View category "Snacks" while online.
  3. Disconnect internet (go offline).
  4. View category "Dairy". The products shown are Snacks.
- **Root cause:** `lib/features/catalog/data/catalog_repository.dart` line 46 used cache key `'page.${cursor ?? 'first'}'` without `categoryId`, causing all categories to overwrite the same cache entries.
- **Fix:** Formatted cache key as `'page.$categoryId.${cursor ?? 'first'}'`.
- **Test:** `test/catalog_cache_category_test.dart` → `offline cache keeps separate pages for different categories`
- **Commits:** test `10a4ba1` → fix `e63ff92`

---

## BUG-9: CatalogController loadMore duplicate items on rapid scrolling

- **Symptom:** Fast scrolling down a catalog list duplicates product cards.
- **Steps to reproduce:**
  1. Open the "All products" listing.
  2. Fling down quickly to scroll to the end of page 1.
  3. Multiple scroll triggers invoke `loadMore()` concurrently.
  4. Page 2 items appear duplicated in the list.
- **Root cause:** `lib/features/catalog/presentation/catalog_controller.dart` line 99 checked `if (!state.hasMore) return;` but lacked an in-flight guard for `state.isLoadingMore` or `state.isLoadingFirstPage`. Both calls read the same `nextCursor` and appended identical items.
- **Fix:** Added guards `state.isLoadingMore || state.isLoadingFirstPage || state.isRefreshing` at the top of `loadMore()`.
- **Test:** `test/catalog_load_more_race_test.dart` → `concurrent loadMore calls do not duplicate items`
- **Commits:** test `12fe954` → fix `c174b7e`

---

## BUG-10: SearchController 1-char crash and stale results race

- **Symptom:** Typing a single character in the search field triggers a server error ("Query too short"). Typing quickly can cause older slow search results to overwrite newer results.
- **Steps to reproduce:**
  1. Tap search and type "m". An error banner appears ("Query too short").
  2. Type "milk" quickly. Results for "mi" can overwrite "milk" if the network response for "mi" arrives second.
- **Root cause:** `lib/features/search/search_controller.dart`:
  - Called `search(query.trim())` for 1-char queries, triggering backend 400 `QUERY_TOO_SHORT`.
  - Had no sequence or cancellation token to discard responses from superseded queries.
- **Fix:** Ignored queries with length < 2 (clearing results without error), and added an incrementing `_searchSequence` to discard stale async responses.
- **Test:** `test/search_controller_test.dart` → `single character query does not hit API and does not produce error`, `stale slow response does not overwrite newer fast response`
- **Commits:** test `4ba774a` → fix `caefb54`

---

## Suspicious but NOT a bug

- **`Coupon.isExpired` boundary:** Treats the exact millisecond of expiry as expired via `!expiresAt.isAfter(now.toUtc())`. Verified against `lib/mock_server/mock_server.dart` which uses `now.isAfter(coupon.expiresAt) || now.isAtSameMomentAs(coupon.expiresAt)` — the domain logic strictly matches the backend contract.
- **Percent discount rounding:** `subtotalPaise * value ~/ 100` uses integer truncation (`~/`), rounding down to the nearest paisa. Verified against `BUSINESS_RULES.md` §3 which explicitly mandates "rounded down to the paisa".
- **Coupon below minimum order:** A coupon below minimum order remains attached to the cart with `discount = 0` rather than being ejected. Verified against `BUSINESS_RULES.md` §3 ("If the cart is below the minimum, the coupon stays applied but gives no discount until the minimum is reached. The customer can still place the order").
- **Product discount percentage:** `(mrpPaise - pricePaise) * 100 ~/ mrpPaise` floors the percentage. This is correct for display badges (e.g. 19.8% off displays as 19% OFF).
