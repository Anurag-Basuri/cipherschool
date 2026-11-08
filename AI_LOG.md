# AI usage log

Tools used: Antigravity, Claude 3.5 Sonnet / Claude Opus 4.6, Gemini 3.8

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | Analyze the QuickKart codebase against BUSINESS_RULES.md, API_CONTRACT.md, and ARCHITECTURE.md to identify all user-facing bugs. | Cross-checked each candidate against business rules to reject false positives (e.g. verified percent discount rounding down is correct) and prioritized 10 genuine bugs. |
| 2 | Design a failing test and fix for QK-101 (cart mutations not persisting after app restart). | Implemented `test/cart_persistence_test.dart` and refactored `CartController` to route all mutations through a unified `_commit(Cart)` method. |
| 3 | How to resolve QK-102 where ApiClient's 10-minute cache serves stale prices and orders. | Evaluated options (removing cache vs cache busting vs bypass parameter). Decided to keep the cache for general catalog browsing but added `bypassCache: true` for pull-to-refresh, order queries, and config loading. |
| 4 | Design test and implementation for CartReconciler.reconcile contract. | Implemented pure domain test suite `test/cart_reconciler_test.dart` covering price shifts, stock exhaustion, discontinued items, and coupon rules, followed by chunked batch reconciliation in `CartReconciler`. |
| 5 | How to prevent duplicate order creation on flaky networks during checkout timeouts. | Implemented idempotency key generation tied to a deterministic cart fingerprint, persisting the key to `KeyValueStore` and sending it in the `Idempotency-Key` header with single-retry recovery. |
| 6 | How to implement UpdatePolicy.evaluate for semantic versions segment-by-segment. | Built `test/update_policy_test.dart` testing dotted numbers (1.4 vs 1.4.0, 1.4.0 vs 1.10.2) and malformed string handling, then implemented the evaluator. |
| 7 | How to safely subscribe to ConfigRepository.remoteUpdates in AppConfigController without leaking listeners. | Subscribed in `AppConfigController.build()` with `ref.onDispose(subscription.cancel)` so updates apply live across the app and listeners are cleanly disposed. |

## When the AI was wrong or misleading (at least 3)

### 1.
- **What it suggested:** Removing `ApiClient`'s response cache entirely to fix QK-102.
- **Why it was wrong:** Discarding the cache throws away critical network bandwidth savings on flaky 2G/3G mobile networks, violating the architecture design goal documented in `ARCHITECTURE.md` and `api_client.dart` ("Saves bandwidth on flaky campus / mobile networks").
- **How I noticed:** Reviewing the comments and intent in `lib/core/network/api_client.dart`. The cache exists intentionally for catalog browsing; only user-triggered refreshes, dynamic orders, and config updates need fresh responses.
- **What I did instead:** Preserved the in-memory cache and introduced an optional `bypassCache: bool` parameter (default `false`), selectively passing `true` for pull-to-refresh (`CatalogController.refresh`), order history (`OrderApi.getOrders`), and config refresh (`ConfigRepository.load`).

### 2.
- **What it suggested:** Flagging `Coupon.isExpired` as a bug because `!expiresAt.isAfter(now.toUtc())` treats the exact millisecond of expiry as expired.
- **Why it was wrong:** In `lib/mock_server/mock_server.dart`, the backend checks `now.isAfter(coupon.expiresAt) || now.isAtSameMomentAs(coupon.expiresAt)`. The client-side logic strictly matches the server behavior. "Fixing" it would have broken parity with the backend.
- **How I noticed:** Checked the actual mock server validation code in `lib/mock_server/mock_server.dart` line 440 before touching any code.
- **What I did instead:** Kept `Coupon.isExpired` untouched and documented it under "Suspicious but NOT a bug" in `BUGS.md`.

### 3.
- **What it suggested:** Using a random UUID generated on every button press as the `Idempotency-Key`.
- **Why it was wrong:** If a network timeout occurs and the user presses "Place order" again (or the client retries), a newly generated UUID will create a second, duplicate order on the server. The entire point of idempotency is that retries of the *same* cart send the *same* key.
- **How I noticed:** Simulated a network timeout with `harness.server.chaos.lostOrderResponses = 1`. A new key caused two orders to be created in `harness.server.getOrders()`.
- **What I did instead:** Derived the idempotency key from a hash of the cart contents (`productId:quantity:unitPricePaise;coupon`), persisted it in `KeyValueStore`, and reused the exact same key until order completion cleared the cart.

## What I would NOT trust an AI with in this codebase, and why

1. **Financial and pricing boundary rules:** AI easily confuses `>`, `>=`, `<`, and `<=`, as demonstrated by BUG-4 where `payable > threshold` was written instead of `>=`. Even minor off-by-one errors in pricing logic result in direct financial discrepancies for customers. Every money calculation must be verified against written business rules with explicit boundary unit tests.
2. **Subtle race conditions across async boundaries:** As seen in BUG-3 (rapid cart taps) and BUG-9 (fast catalog scrolling), AI frequently writes straightforward `async/await` flows without considering what happens when a second user interaction occurs while the first `await` is still in flight. Verifying concurrent state updates requires human concurrency reasoning and simulated parallel tests.
3. **Deciding what constitutes a bug vs intentional architecture:** An AI will eagerly "fix" patterns it considers atypical (like custom caching, integer division for paise, or fallback defaults), which can break the contracts expected by hidden evaluation harnesses. Human verification against `ARCHITECTURE.md` and `BUSINESS_RULES.md` is essential before writing code.
