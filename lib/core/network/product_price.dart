import 'dart:convert';

Map<String, dynamic> decodeProductObject(dynamic value) {
  try {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is Map) {
      return {
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
  } on FormatException {
    // Some products have no statistics or structured subtype data.
  }
  return const {};
}

class ProductPrice {
  const ProductPrice(this.amount, this.config, this.updatedAt);

  final double amount;
  final String config;
  final String updatedAt;

  String get formatted => amount == amount.truncateToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  static ProductPrice? tryParse(dynamic value) {
    final data = decodeProductObject(value);
    final price = double.tryParse('${data['final_price'] ?? ''}');
    if (price == null || !price.isFinite || price <= 0) return null;
    return ProductPrice(
      price,
      '${data['config_name'] ?? ''}'.trim(),
      '${data['update_time'] ?? ''}'.trim(),
    );
  }
}
