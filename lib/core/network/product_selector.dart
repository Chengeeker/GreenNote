import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

class ProductSelectorData {
  const ProductSelectorData({
    required this.items,
    required this.filters,
    required this.sorts,
    required this.subScores,
  });
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> filters;
  final Map<String, String> sorts;
  final Map<String, String> subScores;

  static ProductSelectorData parse(String source) {
    final doc = html.parse(source);
    String clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final items = <Map<String, dynamic>>[
      for (final row in doc.querySelectorAll('.phone-item[data-product-id]'))
        {
          'id': row.attributes['data-product-id']!,
          'title': clean(row.querySelector('.phone-name')?.text ?? ''),
          'pic': row.querySelector('.phone-image img')?.attributes['src'] ?? '',
          'specs': clean(row.querySelector('.phone-specs')?.text ?? ''),
          'price': clean(row.querySelector('.phone-price')?.text ?? '')
              .replaceAll(' ', ''),
          'tags': [
            for (final tag in row.querySelectorAll(
              '.phone-specs-tags .tag-item',
            ))
              clean(tag.text),
          ],
        },
    ];
    final filters = <Map<String, dynamic>>[];
    for (final group in doc.querySelectorAll('.filter-section[data-group]')) {
      final label = group.querySelector('.filter-section-title')?.clone(true);
      label?.querySelectorAll('svg,.expand-button').forEach((e) => e.remove());
      final options = <Map<String, String>>[
        for (final option in group.querySelectorAll('.filter-modal-item[data]'))
          {'title': clean(option.text), 'value': option.attributes['data']!},
      ];
      if (options.isNotEmpty) {
        filters.add({
          'id': group.attributes['data-group']!,
          'title': clean(label?.text ?? ''),
          'options': options,
        });
      }
    }
    return ProductSelectorData(
      items: items.where((item) => item['title'] != '').toList(growable: false),
      filters: filters,
      sorts: {
        for (final row in doc.querySelectorAll('.filter-item[data]'))
          if (row.attributes['data'] != 'child')
            row.attributes['data']!: clean(row.text),
      },
      subScores: {
        for (final row in doc.querySelectorAll('.modal-item[data]'))
          row.attributes['data']!: clean(row.text),
      },
    );
  }
}

class ProductSelectorSource {
  ProductSelectorSource({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: 'https://m.coolapk.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36',
              },
            ),
          );
  final Dio _client;
  ProductSelectorData? configuration;
  void dispose() => _client.close(force: true);

  Future<ProductSelectorData> load(
    int page, {
    String keyword = '',
    String sort = 'default',
    Map<String, List<String>> filters = const {},
  }) async {
    // This official POST only searches public products; it never receives app cookies.
    if (configuration == null) {
      final response = await _client.get<String>(
        '/mp/productSelector/configSearch',
        queryParameters: {'callFunction': 'indexSearch'},
        options: Options(responseType: ResponseType.plain),
      );
      final source = response.data ?? '';
      configuration = ProductSelectorData.parse(source);
      if (configuration!.sorts.isEmpty) {
        throw const FormatException('选机中心页面结构已变化，请稍后重试');
      }
      if (page == 1 &&
          keyword.isEmpty &&
          sort == 'default' &&
          filters.isEmpty) {
        return configuration!;
      }
    }
    final response = await _client.post<dynamic>(
      '/mp/productSelector/configSearch',
      queryParameters: {'page': page, 'keyWord': keyword, 'sortValue': sort},
      data: {
        for (final group in filters.entries)
          for (var i = 0; i < group.value.length; i++)
            'selectedFilters[${group.key}][$i]': group.value[i],
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'X-Requested-With': 'XMLHttpRequest'},
      ),
    );
    final root = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (root is! Map || root['data'] is! String) {
      throw const FormatException('选机中心返回了无法识别的数据');
    }
    final status = int.tryParse('${root['status'] ?? 200}');
    if (status != null && status != 0 && status != 200) {
      throw FormatException('${root['message'] ?? '无法读取机型'}');
    }
    return ProductSelectorData.parse(root['data'] as String);
  }
}
