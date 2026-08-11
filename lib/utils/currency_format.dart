/// Formats a rupee amount using Indian digit grouping (lakh/crore
/// style, e.g. 1234567 -> "12,34,567") rather than the international
/// thousands grouping `NumberFormat` defaults to. Every other ₹ price
/// in the app so far (a nightly rate, one booking's total) has been
/// small enough that grouping never mattered, so this only exists
/// here - host earnings totals routinely run into lakhs and read
/// poorly as a solid string of seven digits.
String formatInr(num amount, {bool showDecimals = false}) {
  final isNegative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(showDecimals ? 2 : 0);
  final parts = fixed.split('.');
  final wholePart = parts[0];
  final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

  final String grouped;
  if (wholePart.length <= 3) {
    grouped = wholePart;
  } else {
    final lastThree = wholePart.substring(wholePart.length - 3);
    final rest = wholePart.substring(0, wholePart.length - 3);
    final buffer = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      final posFromRight = rest.length - i;
      buffer.write(rest[i]);
      if (posFromRight > 1 && posFromRight.isOdd) {
        buffer.write(',');
      }
    }
    grouped = '$buffer,$lastThree';
  }

  return '${isNegative ? '-' : ''}₹$grouped$decimalPart';
}

/// Compact form for tight spaces (chart bar labels etc): 150000 ->
/// "₹1.5L", 12000000 -> "₹1.2Cr", anything under a lakh falls back to
/// [formatInr] since there's no shorter way to write it.
String formatInrCompact(num amount) {
  final abs = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (abs >= 10000000) {
    return '$sign₹${(abs / 10000000).toStringAsFixed(abs % 10000000 == 0 ? 0 : 1)}Cr';
  }
  if (abs >= 100000) {
    return '$sign₹${(abs / 100000).toStringAsFixed(abs % 100000 == 0 ? 0 : 1)}L';
  }
  if (abs >= 1000) {
    return '$sign₹${(abs / 1000).toStringAsFixed(abs % 1000 == 0 ? 0 : 1)}k';
  }
  return formatInr(amount);
}
