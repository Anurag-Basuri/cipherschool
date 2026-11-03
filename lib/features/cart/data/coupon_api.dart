import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../domain/coupon.dart';

final couponApiProvider = Provider<CouponApi>(
  (ref) => CouponApi(ref.watch(apiClientProvider)),
);

class CouponApi {
  CouponApi(this._client);

  final ApiClient _client;

  /// Returns the coupon rules. Throws [ClientException] with code
  /// `COUPON_NOT_FOUND` (404) or `COUPON_EXPIRED` (409).
  Future<Coupon> validate(String code) async {
    final json = await _client.post(
      '/v1/coupons/validate',
      body: {'code': code.trim().toUpperCase()},
    ) as Map<String, dynamic>;
    return Coupon.fromJson(json);
  }
}
