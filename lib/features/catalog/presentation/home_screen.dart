import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/domain/update_policy.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/paginated_catalog_view.dart';
import 'widgets/product_card.dart';

final dealsProvider = FutureProvider<CatalogPage>(
  (ref) => ref.watch(catalogRepositoryProvider).getDeals(),
);

final dismissedOptionalUpdateProvider = StateProvider<String?>((ref) => null);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigControllerProvider);
    final appVersion = ref.watch(appVersionProvider);

    // 1. Version gate: required update blocks the app
    final updateReq = UpdatePolicy.evaluate(
      currentVersion: appVersion,
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );

    if (updateReq == UpdateRequirement.required) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 72, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Update required',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your app version ($appVersion) is no longer supported. '
                    'Please update to continue using QuickKart.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Update now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final storeName = ref.watch(mockServerProvider).storeName;
    final dismissedVersion = ref.watch(dismissedOptionalUpdateProvider);
    final showOptionalUpdate = updateReq == UpdateRequirement.optional &&
        dismissedVersion != config.latestVersion;

    final layoutSections = HomeLayout.parse(config.homeSectionsJson);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: PaginatedCatalogView(
        categoryId: kAllProductsCategory,
        headerSlivers: [
          // Store Closed Banner
          if (!config.storeOpen)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_mall_directory_outlined,
                        color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.storeClosedMessage,
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Optional update banner
          if (showOptionalUpdate)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.system_update, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Update available (${config.latestVersion})',
                        style: TextStyle(color: Colors.blue.shade900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        ref
                            .read(dismissedOptionalUpdateProvider.notifier)
                            .state = config.latestVersion;
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Search Box
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
                child: InputDecorator(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search for products',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Search "milk", "chips"…',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            ),
          ),

          // Server-Driven Sections in Configured Order
          for (final section in layoutSections) ...[
            if (section == HomeSection.banner && config.homeBanner != null)
              SliverToBoxAdapter(
                child: _HomeBannerWidget(banner: config.homeBanner!),
              ),
            if (section == HomeSection.categories)
              const SliverToBoxAdapter(child: _CategoriesRow()),
            if (section == HomeSection.deals)
              const SliverToBoxAdapter(child: _DealsSection()),
            if (section == HomeSection.allProducts)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'All products',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _HomeBannerWidget extends StatelessWidget {
  const _HomeBannerWidget({required this.banner});

  final HomeBanner banner;

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('0xFF$clean'));
    } catch (_) {
      return const Color(0xFFFF6F00);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _parseColor(banner.colorHex),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            banner.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (banner.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              banner.subtitle,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _DealsSection extends ConsumerWidget {
  const _DealsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(dealsProvider);

    return dealsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (page) {
        if (page.items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '⚡ Top Deals',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: page.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 160,
                    child: ProductCard(product: page.items[index]),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoriesProvider),
            child: const Text("Couldn't load categories. Retry"),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final c = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => CategoryScreen(category: c)),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.green.shade50,
                      child:
                          Text(c.emoji, style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(height: 4),
                    Text(c.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
