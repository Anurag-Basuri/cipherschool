# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?**
- **What does the user see for each kind of change?** (price up / down,
  out of stock, quantity reduced, discontinued, coupon removed)
- **What happens to out-of-stock / discontinued items?**
- **Offline-built carts:**
- **Alternatives considered and rejected:**

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** (key generation, lifetime, storage)
- **What does the user see on timeout / lost response?**
- **Edge cases you handled:**
- **Edge cases you know you did NOT handle:**

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:**
- **How live updates propagate, and how you avoid leaks:**
- **Force / optional update UX:**
- **Store closed UX:**
- **Server-driven home: robustness to bad config:**

## 4. Feature 3 (if attempted)

## 5. Other decisions

- Packages added (and why):
- Refactors you made to the existing code (and why):

## 6. Looking ahead

- What would you do with one more week?
- What breaks first at 10× users (10k DAU)? What would you change?
- How would you ship a hotfix for a critical bug without a store release?
