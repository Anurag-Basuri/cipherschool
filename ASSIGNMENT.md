# QuickKart: Flutter Engineer Assignment

Welcome! 👋 Thanks for taking the time to do this.

QuickKart is a 10-minute delivery app (think Blinkit / Zepto) with about
500–1,000 daily active users. This repo is a **real-looking codebase built
by a previous team**. It works, mostly. Your job is the work you would
actually do in your first weeks here:

1. **Find and fix the bugs** that real users are hitting.
2. **Build two production features** on top of the existing code.
3. *(Optional)* Build a third feature.
4. **Explain your decisions** in writing and in a short video.

> **Same assignment for everyone.** Every candidate gets the same app, code
> and brief. Submissions are compared; copied work disqualifies everyone
> involved.

> You **are allowed and encouraged to use AI tools** (Claude, ChatGPT,
> Copilot, Cursor…). We use them every day. What we evaluate is your
> **judgment**: what you ask, what you accept, what you reject, and whether
> you understand and can defend every line you submit. In the next round you
> will change this code **live** while we watch, so make sure it is truly
> yours.

---

## ⏱ Timeline

| | |
|---|---|
| Total time | **3 days (72 hours)** from when you receive the repo |
| Expected effort | about 18–22 focused hours with AI assistance |
| Deadline | stated in the email you received; late submissions are not accepted |

Plan for depth over breadth. The shared Google Doc and this file contain the same brief. **A smaller amount of excellent work beats a
large amount of half-working work.**

---

## 🚀 Getting started

See [README.md](README.md) for setup. In short:

```bash
flutter create . --project-name quickkart --platforms=android,ios   # generates platform folders only
flutter pub get
flutter test
flutter run
```

There is **no backend to set up**. The app ships with an in-process mock
backend (`lib/mock_server/`) that behaves like a real one: network latency,
random failures, lost responses, prices that change, stock that runs out,
remote config that can be published live, realtime order updates and push
messages. It persists its data on the device, so it survives app restarts
just like a real server.

Open **Dev tools** (🐞 icon on the home screen) to play the role of the
backend team, the Firebase console and a bad mobile network.

Read these before you start coding:

- [BUSINESS_RULES.md](docs/BUSINESS_RULES.md): how the product must behave (the source of truth).
- [API_CONTRACT.md](docs/API_CONTRACT.md): the backend API.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is organised, and the **public contract** you must not break.

---

## Part A: Bug hunt (required)

Users have been complaining. Support has filed two tickets so far:

> **QK-101: "Items I removed come back"**
> *"I removed the chips and reduced the milk to 1, closed the app, and when I
> opened it again the chips were back and the milk was 2 again. The cart
> badge shows the wrong number after reopening the app."*
> (Reported by many users, Android & iOS.)

> **QK-102: "Prices don't update until I restart the app"**
> *"The price of tomatoes changed, but pull-to-refresh still shows the old
> price. My orders page also doesn't show the order I just placed. Everything
> updates only after I kill and reopen the app."*

**These two are just examples.** The app contains **several more bugs of the
same kind**: real, behavioural bugs that affect users (wrong money, wrong
data, crashes, races, offline issues…). Nobody has filed tickets for them
yet. Finding them is part of the assignment, and **how many you find, and
how well you prove them, matters**.

What counts as a bug: the app doesn't behave as described in
`BUSINESS_RULES.md` / `API_CONTRACT.md`, crashes or throws, loses or corrupts
data, shows wrong information, or behaves incorrectly under realistic
conditions (slow network, offline, fast taps, app restarts…).
Lint warnings, code style and "I would have structured this differently"
are **not** bugs.

⚠️ **Not everything that looks suspicious is a bug.** Some code is correct
on purpose. If you "fix" correct behaviour, it counts against you, so verify
against the business rules before changing anything.

### For every bug you fix, document in `BUGS.md`:

1. **Symptom**: what a user would see.
2. **Steps to reproduce**: in the app (using Dev tools if needed).
3. **Root cause**: 2–4 lines. Point to the file/function.
4. **Fix**: what you changed and why this is the right fix.
5. **Proof**: a **test that failed before your fix and passes after**.
   Commit the failing test **before** the fix commit (we check the git
   history), e.g.
   `test: reproduce cart not persisted after decrement (QK-101)` →
   `fix: persist cart on every mutation (QK-101)`.

Bugs that are not real (or are a misreading of the rules) get no credit;
a real bug without a reproducing test gets partial credit.

---

## Part B: Feature 1: Offline cart reconciliation & safe checkout (required)

### Context
Users build carts on bad networks, often over many minutes, sometimes while
fully offline. By the time they check out, the world has changed: prices
drift, items sell out, quantity limits change, products are discontinued,
coupons expire. Today the app just sends the order and shows whatever error
the server returns, so users see cryptic failures. Worse, finance has
reported customers **charged twice for the same order** on slow networks.

### What to build

1. **Implement `CartReconciler.reconcile`**
   (`lib/features/cart/application/cart_reconciler.dart`). The contract is
   documented in the code; hidden tests check it exactly.
2. **Wire reconciliation into the app.** You decide *when* it runs (e.g.
   opening the cart, coming back online, before checkout, after a `409` from
   the server…) and *how the user experiences it*. Requirements:
   - The user must **never be charged an amount, price or quantity they have
     not seen** (see BUSINESS_RULES.md §5). Price **drops** may be applied
     silently; anything else must be shown to the user and acknowledged.
   - The user must clearly understand **what changed** (not just "cart
     updated").
   - It must work for a cart that was built **offline** and synced later.
   - Don't throw away the user's intent carelessly (e.g. what happens to an
     out-of-stock item? You decide, and justify it).
3. **Make checkout safe** (`CheckoutController.placeOrder`):
   - **An order must never be created twice**: not with retries, not with
     lost responses (try *Dev tools → Lose next*), not with double taps,
     not if the user taps "Place order" again after a timeout.
     The backend supports an `Idempotency-Key` header (see API_CONTRACT).
   - If the server says prices/stock/coupon changed, or reconciliation finds
     changes that need review, return `CheckoutNeedsReview` and **do not
     place the order** until the user has seen the updated cart.
   - Handle offline / timeout / store-closed with clear, honest messages.
     ("Your order may have been placed. Check *My orders*" is honest;
     "Something went wrong" is not.)

Use **Dev tools → "Create conflicts for my cart"** to test the whole flow.

---

## Part C: Feature 2: Change the app without a store release (required)

### Context
Shipping a new build through Play Store / App Store review takes days. The
business needs to control the app **remotely and instantly**: close the
store during a rain spike, force users off a buggy version, run a Diwali
banner, reorder the home screen for a sale. We use a Remote Config system
(simulated by the mock server; it behaves like Firebase Remote Config,
including a realtime "config updated" listener).

### What to build

1. **Config that survives bad networks.** Implement caching in
   `ConfigRepository.load()`: on success persist the values; on failure use
   the **last known good config**; with nothing cached use defaults. It must
   never throw. The app must start normally offline.
2. **Live updates.** `AppConfigController` must keep itself up to date when
   config is published (subscribe to `ConfigRepository.remoteUpdates` in its
   `build()`), so changes apply **within seconds, without restarting the
   app**, and without leaking listeners.
3. **Version gate.** Implement `UpdatePolicy.evaluate` (contract in the
   code) and use it:
   - `required` → block the app with a full-screen "Update required" page
     (with a button to `update_url`). It must not be dismissible and must
     also trigger **mid-session** if config changes while the app is open.
   - `optional` → a dismissible prompt; once dismissed, don't nag again for
     the same `latest_version`.
   - Test it with *Dev tools → App version* and the config presets.
4. **Store kill switch.** When `store_open` is `false`: show the
   `store_closed_message` prominently, let users browse, but **prevent
   checkout**, also if the store closes while the user is on the cart
   screen. `CheckoutController.placeOrder` must return `CheckoutFailure`
   **without sending the order request** when the app already knows the
   store is closed.
5. **Server-driven home screen.** Implement `HomeLayout.parse` (contract in
   the code) and render the home screen from `home_sections`: `banner`
   (from `home_banner`), `categories`, `deals` (`CatalogRepository.getDeals`),
   `all_products`, in the configured order. Bad config must never break the
   home screen.

---

## Part D: Feature 3: Live order tracking (optional, bonus)

Only attempt this after Parts A–C are solid. A polished Part D will **not**
make up for weak required parts, and **broken optional work costs points**.

- Implement `OrderTrackingRepository.watchOrder` on top of the realtime
  listener (`watchOrderDocument`, which works like a Firestore snapshot listener).
- Show live status (placed → packed → out for delivery → delivered) for
  active orders on *My orders* / an order details page.
- Show an in-app notification when `pushMessages` (simulated FCM
  foreground messages) reports a status change, and tapping it opens the
  order.
- It must be correct after an app restart and must not leak listeners.
- Use *Dev tools → Orders → Advance* to move orders forward.

**Extra bonus:** wire a real **Firebase** project (your own free project)
behind the existing abstractions (Remote Config / Firestore / FCM) *without*
breaking the mock-based build. Explain how in `DECISIONS.md`.

---

## 📦 What to submit

1. Commit **all** your work, including `BUGS.md`, `DECISIONS.md` and
   `AI_LOG.md`. Uncommitted changes are **not** included in the bundle.
2. Note your final commit SHA: `git rev-parse HEAD`
3. Create the bundle (one file with your whole repo and history):
   `git bundle create <rollnumber>.bundle --all`
4. Upload the `.bundle` file in the submission form, with your commit SHA and
   video link, before the deadline. We grade exactly that commit; late
   submissions are not accepted.

## ✅ Mandatory deliverables

Every item is required. **A submission missing any of them is not evaluated.**

**Templates are strict.** `BUGS.md`, `DECISIONS.md` and `AI_LOG.md` are already
in this repo. Fill them **in place**: keep every heading in the same order, do
not rename, move or delete the files, and do not switch to another format (no
PDF / Word / Google Doc). Write "Not applicable" under a heading that doesn't
apply instead of deleting it. Submissions that ignore the templates lose the
communication marks (15%).

| Deliverable | Where | Must contain |
|---|---|---|
| Code | the `.bundle` file uploaded in the form | all changes committed, full git history kept |
| `BUGS.md` | repo root | one block per bug: symptom, steps, root cause, fix, test, test + fix commit SHAs |
| `DECISIONS.md` | repo root | every heading answered (Feature 3: "Not attempted" if skipped) |
| `AI_LOG.md` | repo root | tools used; 5–10 significant prompts and what you did with each; **at least 3** cases where the AI was wrong and how you noticed |
| Video | link in the form | see rules below |
| Tests | `test/` | one failing-first test per bug + tests for Feature 1 and 2 logic |

### Video rules
- **5–7 minutes** (stopped at 7). **Camera on** the whole time + screen share, in English.
- Loom / Google Drive / YouTube (unlisted), viewable **without login** (test in incognito).
- Show, in this order:
  1. Conflict flow: Dev tools → *Create conflicts for my cart* → checkout.
  2. Lost response: Dev tools → *Lose next* → place order → only one order exists.
  3. Offline start: go offline, restart the app, it still works.
  4. Store closed and force update (Dev tools presets).
  5. Code walkthrough of your reconciliation and checkout, explaining **why**.

### Git rules
- Commit early and often; one giant commit at the end is a red flag.
- For every bug, the **test commit comes before the fix commit**.

### Before you submit
- [ ] `flutter analyze` has no errors and `flutter test` passes
- [ ] the app runs on Android or iOS
- [ ] the three templates are filled in place, all headings kept
- [ ] the video link opens in an incognito window
- [ ] everything is committed, and you have your bundle file and final commit SHA

---

## 🧮 How you will be evaluated

| Area | Weight |
|---|---|
| Part A: Bug hunt (bugs found × difficulty, quality of proof) | 25% |
| Part B: Feature 1: reconciliation & safe checkout | 30% |
| Part C: Feature 2: remote control without a release | 20% |
| Part D: Feature 3 (optional) | up to +10% |
| `DECISIONS.md`, `AI_LOG.md`, video | 15% |
| Code quality and your own tests | 10% |

Parts B and C are checked with **automated hidden tests** against the
contracts in [ARCHITECTURE.md](docs/ARCHITECTURE.md), plus human review of
UX, code quality and tests. Required parts are graded first.

## 📏 Rules

- **Do not modify** `lib/mock_server/**` or `lib/core/network/transport.dart`.
  They are replaced with the original versions during grading.
  You may *read* them and use the server's admin methods in your tests.
- **Do not rename or move** anything listed in the *Public contract*
  section of ARCHITECTURE.md. You may add to it.
- You may add packages if you can justify them in `DECISIONS.md`.
- Individual work. Do not share your solution or bug list with other
  candidates. Similar submissions are detected and both are disqualified.
- If something in the brief is ambiguous, **make a reasonable decision and
  document it** in `DECISIONS.md`. That is part of the job. (You can email
  us, but expect the answer "use your judgment".)

Good luck, and have fun with it. 🪔
