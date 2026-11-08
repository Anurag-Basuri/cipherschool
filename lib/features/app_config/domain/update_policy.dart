import 'dart:math';

/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
///
/// Contract (hidden tests check this exactly - see ASSIGNMENT.md, Feature 2):
/// * Versions are dotted numbers like `1.4.0`, `1.10.2`, `2.0`. Compare them
///   numerically, segment by segment. Missing segments count as 0
///   (`1.4` == `1.4.0`).
/// * `current < minSupported`  -> [UpdateRequirement.required]
/// * `current < latest`        -> [UpdateRequirement.optional]
/// * otherwise                 -> [UpdateRequirement.none]
/// * If ANY of the three versions is malformed (empty, letters, negative
///   numbers, ...) return [UpdateRequirement.none]. A bad value in the
///   config console must never lock users out of the app.
class UpdatePolicy {
  const UpdatePolicy._();

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    final current = _parseVersion(currentVersion);
    final minSupported = _parseVersion(minSupportedVersion);
    final latest = _parseVersion(latestVersion);

    if (current == null || minSupported == null || latest == null) {
      return UpdateRequirement.none;
    }

    if (_compareVersions(current, minSupported) < 0) {
      return UpdateRequirement.required;
    }
    if (_compareVersions(current, latest) < 0) {
      return UpdateRequirement.optional;
    }
    return UpdateRequirement.none;
  }

  static List<int>? _parseVersion(String version) {
    final trimmed = version.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split('.');
    if (parts.isEmpty) return null;
    final segments = <int>[];
    for (final p in parts) {
      if (p.isEmpty) return null;
      final val = int.tryParse(p);
      if (val == null || val < 0) return null;
      segments.add(val);
    }
    return segments;
  }

  static int _compareVersions(List<int> a, List<int> b) {
    final maxLen = max(a.length, b.length);
    for (var i = 0; i < maxLen; i++) {
      final segA = i < a.length ? a[i] : 0;
      final segB = i < b.length ? b[i] : 0;
      if (segA < segB) return -1;
      if (segA > segB) return 1;
    }
    return 0;
  }
}
