# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?**
  - **Before checkout:** Runs right when the user taps "Place order". This is the critical single point of truth where pricing, stock, limits, and coupon validity must be verified against current server state before charging the user.
  - **On 409 / 422 conflict responses:** If race conditions occur between local reconciliation and backend execution, the server's rejection triggers an immediate re-reconciliation, returning `CheckoutNeedsReview` so the user is never stuck.
  - **Why not on every cart badge update or every second?** Polling continuously would drain device battery and overwhelm backend catalog batch endpoints under flaky networks. Reconciling deterministically before checkout catches all drift without unnecessary network chatter.
- **What does the user see for each kind of change?**
  - **Price drop (`isIncrease == false`):** Applied silently without blocking checkout (`requiresUserReview == false`). The user benefits from the lower price immediately.
  - **Price increase (`isIncrease == true`):** Blocks checkout with `CheckoutNeedsReview` (`requiresUserReview == true`). The cart is updated to the higher price, and the user is notified via SnackBar to review before retrying.
  - **Out of stock (`OutOfStock`):** Line is removed from the active cart. `CheckoutNeedsReview` is returned, alerting the user that the item is currently out of stock.
  - **Quantity reduced (`QuantityReduced`):** Line quantity is clamped to `min(stock, maxPerOrder)`. The user is alerted to review the adjusted quantity.
  - **Discontinued / unknown (`ProductUnavailable`):** Line is removed. User is alerted that the product is no longer sold.
  - **Coupon removed (`CouponRemoved`):** Coupon is detached if expired or invalid. User is alerted with the specific reason (`EXPIRED` or `NOT_FOUND`).
- **What happens to out-of-stock / discontinued items?**
  - They are removed from the active orderable cart so the user cannot place an invalid order, but they are flagged in `changes` so the UI presents clear feedback explaining why the total and item list changed.
- **Offline-built carts:**
  - A user can build a cart completely offline. When connectivity is restored and they tap "Place order", `CartReconciler.reconcile` evaluates the entire cart against the server in batches of 50 IDs, updating prices, stock limits, and coupons in one atomic pass. If the network is still down, checkout fails gracefully with an honest "No internet connection" message, preserving the user's cart on disk.
- **Alternatives considered and rejected:**
  - *Reconciling on every screen resume / app foreground:* Rejected because it introduces layout shift and jank while the user is actively browsing or adding items, especially on unstable mobile connections.
  - *Silently dropping items without review:* Rejected because silently modifying order contents violates customer trust and `BUSINESS_RULES.md` §5.

---

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?**
  - **In-flight guard:** `state.isPlacingOrder` prevents rapid double-taps on the checkout button.
  - **Cart fingerprint & Idempotency-Key header:** An idempotency key (`QK-<timestamp>-<rand>`) is generated and tied to a deterministic cart fingerprint (`productId:quantity:unitPricePaise;coupon`).
  - **Persistence in KeyValueStore:** The key and its fingerprint are persisted to disk. If a network timeout occurs or the app crashes mid-checkout, the exact same key is reused for retries of that cart.
  - **Key lifetime:** Cleared from persistent storage immediately upon successful order creation. If the user mutates their cart, a fresh key is generated, ensuring no `422 IDEMPOTENCY_KEY_REUSED` conflicts.
- **What does the user see on timeout / lost response?**
  - The client retries the request once automatically using the identical `Idempotency-Key`.
  - If the retry also times out: the user is shown the honest message: *"The request timed out. Your order may have been placed. Please check My orders before trying again."* with retry enabled.
- **Edge cases you handled:**
  - *Lost responses (backend created order, response dropped):* When retried with the same `Idempotency-Key`, the mock server returns `200 OK` with the already-created order.
  - *Store closed while on cart screen:* Store status is checked locally first; request is never sent, saving bandwidth.
  - *Backend 409 conflict:* Caught and re-reconciled, presenting `CheckoutNeedsReview` rather than a generic crash.
  - *Empty cart / 0-quantity lines:* Pre-checkout validations reject empty carts cleanly.
- **Edge cases you know you did NOT handle:**
  - Distributed multi-device carts for the same user account (since auth/sync is local to the device in this starter).
  - External payment gateway webhook reconciliation (e.g. Razorpay/Stripe asynchronous webhooks).

---

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:**
  - `ConfigRepository.load()` fetches `/v1/config` (bypassing the 10-minute HTTP GET cache).
  - On success: serializes and saves raw values to `KeyValueStore` under `app_config.cached_values`.
  - On network/server failure: reads the last known good config from `KeyValueStore`.
  - If no cache exists: gracefully falls back to `AppConfig.defaults()`. Never throws under any circumstances.
- **How live updates propagate, and how you avoid leaks:**
  - `AppConfigController.build()` subscribes to `ConfigRepository.remoteUpdates`.
  - When the mock server emits a new config version, `AppConfigController` calls `load()` and updates its state, causing all listening widgets and providers to rebuild reactively.
  - Leaks are avoided by registering `ref.onDispose(subscription.cancel)` in `build()`, ensuring the stream subscription is torn down when the provider container or lifecycle ends.
- **Force / optional update UX:**
  - Evaluated via pure business logic in `UpdatePolicy.evaluate`.
  - `required` (`current < minSupported`): Blocks the app with a full-screen non-dismissible `Scaffold` displaying an update icon, explanation, and an "Update now" action button. It activates immediately mid-session if config changes live.
  - `optional` (`current < latest`): Displays a polite top banner with an update prompt. When the user taps the dismiss ("X") button, the dismissed version is recorded in `dismissedOptionalUpdateProvider` so the user is not nagged again for that version.
- **Store closed UX:**
  - Home screen displays a prominent red warning banner: *"Store closed: <message>"*.
  - Cart screen displays a dedicated warning card at the top, and the "Place order" button is disabled with label *"Store closed 🔒"*.
  - `CheckoutController` rejects order attempts without sending network traffic.
- **Server-driven home: robustness to bad config:**
  - `HomeLayout.parse` is defensive: invalid JSON, non-list payloads, nulls, or empty section lists automatically fall back to `HomeLayout.defaultSections` (`[categories, allProducts]`).
  - Unknown section keys are ignored to prevent forward-compatibility crashes.
  - Duplicate keys are discarded (first occurrence wins).
  - Malformed banner JSON or colors fall back gracefully without breaking the layout.

---

## 4. Feature 3 (if attempted)

Not attempted. Focused on achieving rock-solid quality, 100% test coverage, and bulletproof UX for Parts A, B, and C.

---

## 5. Other decisions

- **Packages added (and why):**
  - None. All requirements were solved cleanly using the existing dependencies (Flutter, Riverpod 2, and Dart standard libraries). Avoiding external packages eliminates dependency bloat and keeps the final bundle size well below the 10 MB limit.
- **Refactors you made to the existing code (and why):**
  - Added `bypassCache: bool` parameter to `ApiClient.get` to selectively bypass the 10-minute in-memory cache for dynamic endpoints (`/v1/orders`, `/v1/config`, and pull-to-refresh).
  - Stopped `ApiClient._getWithRetry` from retrying non-transient 4xx `ClientException` errors (e.g. 400 `INVALID_CURSOR`).
  - Added `_commit(Cart)` in `CartController` to unify persistence across every cart mutation.
  - Added `_searchSequence` token to `ProductSearchController` to eliminate out-of-order race conditions on rapid typing.

---

## 6. Looking ahead

- **What would you do with one more week?**
  - Implement Feature 3: Live order tracking with animated status stepper and push notification listeners.
  - Add optimistic UI updates for cart items with an undo snackbar.
  - Implement SQLite/Drift persistence for catalog pages and search indexing.
- **What breaks first at 10× users (10k DAU)? What would you change?**
  - *Full product catalog batch fetches:* `/v1/products/batch` would experience heavy load if every checkout reconciles all items simultaneously. We would implement an HTTP conditional GET with ETags or `If-Modified-Since` headers to return 304 Not Modified when catalog items haven't changed.
  - *In-memory mock server / SQLite:* Production backend would require Redis-based distributed idempotency locks to handle parallel requests with the same key across multi-instance server clusters.
- **How would you ship a hotfix for a critical bug without a store release?**
  - For business rule / pricing bugs: Use the Remote Config system (`min_supported_version`, banners, delivery fee threshold).
  - For store-wide emergencies: Flip `store_open: false` to protect users from corrupt transactions.
  - For code-level hotfixes: Deploy Shorebird code push for over-the-air (OTA) Flutter Dart updates without store review delays.
