import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';

void main() {
  group('UpdatePolicy.evaluate', () {
    test('returns required when current is below minSupported', () {
      final req = UpdatePolicy.evaluate(
        currentVersion: '1.4.0',
        minSupportedVersion: '1.5.0',
        latestVersion: '2.0.0',
      );
      expect(req, UpdateRequirement.required);
    });

    test('returns optional when current satisfies minSupported but below latest',
        () {
      final req = UpdatePolicy.evaluate(
        currentVersion: '1.5.0',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.6.0',
      );
      expect(req, UpdateRequirement.optional);
    });

    test('returns none when current equals latest and minSupported', () {
      final req = UpdatePolicy.evaluate(
        currentVersion: '2.0.0',
        minSupportedVersion: '1.0.0',
        latestVersion: '2.0.0',
      );
      expect(req, UpdateRequirement.none);
    });

    test('returns none when current is ahead of latest', () {
      final req = UpdatePolicy.evaluate(
        currentVersion: '2.1.0',
        minSupportedVersion: '1.0.0',
        latestVersion: '2.0.0',
      );
      expect(req, UpdateRequirement.none);
    });

    test('compares versions segment by segment numerically (1.4.0 < 1.10.2)',
        () {
      final req = UpdatePolicy.evaluate(
        currentVersion: '1.4.0',
        minSupportedVersion: '1.2.0',
        latestVersion: '1.10.2',
      );
      expect(req, UpdateRequirement.optional);
    });

    test('missing segments count as 0 (1.4 == 1.4.0)', () {
      final req = UpdatePolicy.evaluate(
        currentVersion: '1.4',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.4',
      );
      expect(req, UpdateRequirement.none);
    });

    test('malformed versions return UpdateRequirement.none', () {
      // Empty string
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      // Letters / tags
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0-beta',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      // Negative segment
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '-1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );

      // Invalid characters
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '1.0.0',
          latestVersion: 'latest',
        ),
        UpdateRequirement.none,
      );
    });
  });
}
