# Architecture

```
lib/
├── main.dart                 bootstrap: storage, mock server, restore cart, load config
├── app.dart                  MaterialApp
├── core/
│   ├── providers.dart        root providers (storage, server, ApiClient, app version)
│   ├── network/              ApiClient, exceptions, Transport abstraction
│   ├── storage/              KeyValueStore (SharedPreferences / in-memory)
│   └── utils/money.dart      paise helpers
├── mock_server/              ⛔ simulated backend (do not modify)
└── features/
    ├── catalog/              categories, products, pagination, offline cache
    ├── search/
    ├── cart/                 cart state, persistence, coupons, pricing, reconciliation
    ├── checkout/             placing orders
    ├── app_config/           remote config, update policy, home layout
    ├── orders/               order history, tracking (F3)
    └── dev_tools/            Dev tools screen
```

Each feature follows **data → domain → application/presentation**:

- **data**: API clients (`*Api`), local storage, repositories. Talks JSON.
- **domain**: immutable models and pure business logic (no Flutter, no I/O).
- **application / presentation**: Riverpod notifiers (state + use cases) and
  widgets. Widgets never call APIs directly.

**State management:** Riverpod 2 (`Notifier` / `FamilyNotifier`,
`Provider`, `FutureProvider`). No code generation.

**Networking:** `ApiClient` wraps a `Transport`. In this project the
transport is the mock server; in production it would be HTTP. All failures
surface as `ApiException` subclasses (`NetworkException`,
`ApiTimeoutException`, `ServerException`, `ClientException`).

**Persistence:** `KeyValueStore` (SharedPreferences in the app,
`InMemoryKeyValueStore` in tests). You may switch to Hive/Isar/Drift if you
justify it, but keep the `KeyValueStore` interface working, because tests use it.

**Testing:** see `test/helpers/test_harness.dart`. It builds a
`ProviderContainer` with an in-memory store and an in-memory mock server
(perfect network by default). Use `harness.server.chaos` to simulate bad
networks and `harness.restart()` to simulate an app restart.

---

## Public contract (do not rename, move or remove)

Our automated hidden tests use the following. You **may** change
implementations, add parameters **with defaults**, add new classes and
providers, and add fields. You **may not** rename, move, remove or change the
meaning of:

| File | Symbols |
|---|---|
| `core/providers.dart` | `keyValueStoreProvider`, `mockServerProvider`, `apiClientProvider`, `appVersionProvider` |
| `core/utils/money.dart` | `formatMoney`, `rupeesToPaise` |
| `core/storage/key_value_store.dart` | `KeyValueStore`, `InMemoryKeyValueStore` |
| `core/network/api_exceptions.dart` | all exception classes |
| `features/catalog/data/product_dto.dart` | `ProductDto.fromJson` |
| `features/catalog/data/catalog_repository.dart` | `catalogRepositoryProvider`, `CatalogRepository.getPage({categoryId, cursor, limit})`, `kAllProductsCategory` |
| `features/catalog/data/catalog_api.dart` | `CatalogApi` |
| `features/catalog/domain/product.dart` | `Product`, `Category`, `CatalogPage` |
| `features/catalog/presentation/catalog_controller.dart` | `catalogControllerProvider`, `CatalogController.loadMore/refresh`, `CatalogState.items/isLoadingFirstPage` |
| `features/catalog/presentation/category_screen.dart` | `CategoryScreen(category:)` |
| `features/search/search_controller.dart` | `searchControllerProvider`, `ProductSearchController.search`, `SearchState.query/results` |
| `features/cart/domain/*.dart` | `Cart`, `CartLine`, `Coupon`, `CouponType`, `CartPricing.compute`, all `reconciliation.dart` types |
| `features/cart/application/cart_controller.dart` | `cartControllerProvider`, `CartController.hydrate/add/increment/decrement/remove/applyCoupon/removeCoupon/replace/clear` |
| `features/cart/data/cart_storage.dart` | `cartStorageProvider`, `CartStorage.load/save` |
| `features/cart/application/cart_reconciler.dart` | `cartReconcilerProvider`, `CartReconciler.reconcile` |
| `features/checkout/application/checkout_controller.dart` | `checkoutControllerProvider`, `CheckoutController.placeOrder`, `CheckoutResult` + subclasses |
| `features/app_config/data/config_repository.dart` | `configRepositoryProvider`, `ConfigRepository.load/remoteUpdates` |
| `features/app_config/presentation/app_config_controller.dart` | `appConfigControllerProvider`, `AppConfigController.hydrate` |
| `features/app_config/domain/*.dart` | `AppConfig`, `UpdatePolicy.evaluate`, `UpdateRequirement`, `HomeLayout.parse`, `HomeSection` |
| `features/orders/data/order_tracking_repository.dart` | `orderTrackingRepositoryProvider`, `OrderTrackingRepository.watchOrder` |

Hidden tests build providers **without the widget tree** (a bare
`ProviderContainer`, like `test_harness.dart`), so anything the contract
requires of a provider (e.g. `AppConfigController` staying up to date) must
work there too, not only inside a widget.
