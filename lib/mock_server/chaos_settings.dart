import '../core/network/transport.dart';

/// Controls how badly the simulated network and backend behave.
///
/// Everything is adjustable at runtime from the in-app Dev Tools screen.
class ChaosSettings {
  ChaosSettings({
    this.offline = false,
    this.minLatencyMs = 250,
    this.maxLatencyMs = 1200,
    this.failureRate = 0.08,
    this.orderResponseLossRate = 0.10,
    this.loseNextOrderResponses = 0,
    this.priceDrift = true,
    this.priceDriftInterval = const Duration(seconds: 90),
    this.latencyOverride,
  });

  /// Default behaviour of the app: a realistic, slightly unreliable network.
  factory ChaosSettings.realistic() => ChaosSettings();

  /// A perfect network. Useful in tests.
  factory ChaosSettings.none() => ChaosSettings(
        minLatencyMs: 0,
        maxLatencyMs: 0,
        failureRate: 0,
        orderResponseLossRate: 0,
        priceDrift: false,
      );

  /// Simulates "no internet". Requests fail immediately.
  bool offline;

  int minLatencyMs;
  int maxLatencyMs;

  /// Probability (0..1) that a request fails *before* reaching the server
  /// (either a timeout or a 503).
  double failureRate;

  /// Probability (0..1) that `POST /v1/orders` is processed by the server
  /// but the response never reaches the app (the app sees a timeout).
  double orderResponseLossRate;

  /// Deterministic version of [orderResponseLossRate]: the next N order
  /// responses are lost.
  int loseNextOrderResponses;

  /// When enabled, the price of a random product changes every
  /// [priceDriftInterval] (applied lazily on catalog requests).
  bool priceDrift;
  Duration priceDriftInterval;

  /// Test hook: return a fixed latency for a given request.
  Duration? Function(TransportRequest request)? latencyOverride;
}
