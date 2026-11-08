import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';

void main() {
  group('HomeLayout.parse', () {
    test('parses full valid list keeping specified order', () {
      final sections = HomeLayout.parse(
        '["deals", "banner", "categories", "all_products"]',
      );
      expect(sections, [
        HomeSection.deals,
        HomeSection.banner,
        HomeSection.categories,
        HomeSection.allProducts,
      ]);
    });

    test('ignores unknown section ids', () {
      final sections = HomeLayout.parse(
        '["deals", "stories", "categories", "featured_brands"]',
      );
      expect(sections, [
        HomeSection.deals,
        HomeSection.categories,
      ]);
    });

    test('ignores duplicates with first occurrence winning', () {
      final sections = HomeLayout.parse(
        '["categories", "deals", "categories", "deals"]',
      );
      expect(sections, [
        HomeSection.categories,
        HomeSection.deals,
      ]);
    });

    test('falls back to defaultSections on null input', () {
      expect(HomeLayout.parse(null), HomeLayout.defaultSections);
    });

    test('falls back to defaultSections on empty or whitespace input', () {
      expect(HomeLayout.parse(''), HomeLayout.defaultSections);
      expect(HomeLayout.parse('   '), HomeLayout.defaultSections);
    });

    test('falls back to defaultSections on malformed JSON', () {
      expect(HomeLayout.parse('not json'), HomeLayout.defaultSections);
      expect(HomeLayout.parse('{ "sections": [] }'), HomeLayout.defaultSections);
    });

    test('falls back to defaultSections when no known sections exist', () {
      expect(
        HomeLayout.parse('["mystery1", "mystery2"]'),
        HomeLayout.defaultSections,
      );
    });
  });
}
