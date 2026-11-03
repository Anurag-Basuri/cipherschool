/// Low level "HTTP" abstraction.
///
/// In this assignment the transport is backed by an in-process mock server
/// (see `lib/mock_server`) so you do not need any backend. Replacing it with
/// a real `http`/`dio` implementation would not require changes above
/// [ApiClient].
library;

class TransportRequest {
  const TransportRequest({
    required this.method,
    required this.path,
    this.query = const {},
    this.headers = const {},
    this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;

  /// JSON encoded body (or null).
  final String? body;

  String get cacheKey {
    final sortedKeys = query.keys.toList()..sort();
    final q = sortedKeys.map((k) => '$k=${query[k]}').join('&');
    return '$method $path?$q';
  }

  @override
  String toString() => cacheKey;
}

class TransportResponse {
  const TransportResponse(this.statusCode, this.body);

  final int statusCode;

  /// JSON encoded body.
  final String body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Thrown when the host cannot be reached (device offline, DNS, ...).
class TransportUnreachable implements Exception {
  const TransportUnreachable();
}

/// Thrown when no response arrived in time. The server may or may not have
/// processed the request.
class TransportTimeout implements Exception {
  const TransportTimeout();
}

abstract class Transport {
  Future<TransportResponse> send(TransportRequest request);
}
