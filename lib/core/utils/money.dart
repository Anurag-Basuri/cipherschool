/// Money helpers.
///
/// Every amount inside the app is an integer number of **paise**
/// (1 rupee = 100 paise). Never store money in a `double`.
library;

/// Formats paise for display: `₹50`, `₹49.99` (paise only when there are any).
String formatMoney(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final rest = abs % 100;
  if (rest == 0) return '$sign₹$rupees';
  return '$sign₹$rupees.${rest.toString().padLeft(2, '0')}';
}

/// Converts a rupee amount coming from the (legacy) API into paise.
int rupeesToPaise(num rupees) => (rupees * 100).toInt();
