/// Errors thrown by [ApiClient]. UI code should only ever see these.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  /// Whether retrying the *same* request later could reasonably succeed.
  bool get isTransient;

  @override
  String toString() => '$runtimeType: $message';
}

/// The device has no connectivity (or the server is unreachable).
class NetworkException extends ApiException {
  const NetworkException([super.message = 'No internet connection']);

  @override
  bool get isTransient => true;
}

/// The request did not complete in time. The server MAY have processed it.
class ApiTimeoutException extends ApiException {
  const ApiTimeoutException([super.message = 'The request timed out']);

  @override
  bool get isTransient => true;
}

/// 5xx response.
class ServerException extends ApiException {
  const ServerException(this.statusCode, String message, {this.code})
      : super(message);

  final int statusCode;
  final String? code;

  @override
  bool get isTransient => statusCode != 501;
}

/// 4xx response. [code] is the machine readable `error` field of the body,
/// e.g. `PRICE_CHANGED`. [details] is the optional `details` field.
class ClientException extends ApiException {
  const ClientException(
    this.statusCode,
    String message, {
    this.code,
    this.details,
  }) : super(message);

  final int statusCode;
  final String? code;
  final Object? details;

  @override
  bool get isTransient => false;
}
