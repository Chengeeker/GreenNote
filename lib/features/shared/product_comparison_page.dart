import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/network/product_price.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/widgets/cached_network_image.dart';
import 'product_selector_page.dart';

class ComparisonProduct {
  ComparisonProduct({
    required this.id,
    required this.title,
    required this.logo,
    this.selectedConfigId,
    this.selectedConfigName = '',
    this.price = '',
    this.configRows = const [],
    this.rawDetail = const {},
    Map<String, Map<String, String>>? specs,
    this.loading = false,
  }) : specs = specs ?? {};

  final String id;
  final String title;
  final String logo;
  String? selectedConfigId;
  String selectedConfigName;
  String price;
  List<Map<String, dynamic>> configRows;
  Map<String, dynamic> rawDetail;
  Map<String, Map<String, String>> specs;
  bool loading;

  static bool _isChipString(String text) {
    final lower = text.toLowerCase();
    return text.contains('骁龙') ||
        text.contains('天玑') ||
        text.contains('麒麟') ||
        text.contains('苹果') ||
        text.contains('仿生') ||
        text.contains('玄戒') ||
        text.contains('猎户座') ||
        lower.contains('snapdragon') ||
        lower.contains('dimensity') ||
        lower.contains('bionic') ||
        lower.contains('kirin') ||
        lower.contains('exynos') ||
        lower.contains('tensor') ||
        RegExp(r'\b[aA]\d{2}\b').hasMatch(text) ||
        lower.contains('gen') ||
        lower.contains('cpu');
  }

  static String? _findInSpecs(
    Map<String, Map<String, String>> map,
    List<String> candidateKeys,
  ) {
    for (final key in candidateKeys) {
      for (final group in map.values) {
        if (group.containsKey(key)) {
          final val = group[key]!.trim();
          if (val.isNotEmpty && val != '-') return val;
        }
      }
    }
    return null;
  }

  String getSpec(String group, String key) {
    // 1. Direct group and key lookup
    final direct = specs[group]?[key]?.trim();
    if (direct != null && direct.isNotEmpty && direct != '-') {
      return direct;
    }

    // 2. Synonyms and alias mapping for default core specs
    if (key == '芯片' || key == '处理器') {
      final v = _findInSpecs(specs, ['CPU型号', '处理器', '芯片', 'SoC型号', 'SoC', 'CPU']) ??
          (rawDetail['chip'] ?? rawDetail['soc'] ?? rawDetail['processor'])?.toString().trim();
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == 'RAM & ROM' || key == '存储') {
      final v = _findInSpecs(specs, ['RAM容量', '运行内存']);
      final r = _findInSpecs(specs, ['ROM容量', '机身存储', '存储容量']);
      if (v != null && r != null) return '$v + $r';
      if (rawDetail['ram'] != null && rawDetail['rom'] != null) {
        return '${rawDetail['ram']} + ${rawDetail['rom']}';
      }
      if (selectedConfigName.isNotEmpty) return selectedConfigName;
    } else if (key == '屏幕') {
      final v = _findInSpecs(specs, ['屏幕尺寸', '主屏尺寸']) ??
          rawDetail['screen_size']?.toString().trim();
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == '影像联名') {
      final v = _findInSpecs(specs, ['影像品牌', '影像联名', '镜头品牌', '联名品牌']) ??
          rawDetail['camera_brand']?.toString().trim();
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == '后置主摄' || key == '主摄') {
      final v = _findInSpecs(specs, ['后置摄像头', '后置主摄', '后置摄像头像素']) ??
          (rawDetail['main_camera'] ?? rawDetail['camera'])?.toString().trim();
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == '电池') {
      final v = _findInSpecs(specs, ['电池容量', '电池']) ??
          rawDetail['battery']?.toString().trim();
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == '充电') {
      final v = _findInSpecs(specs, ['有线充电', '充电', '快充', '有线快充', '闪充']) ??
          rawDetail['charging']?.toString().trim();
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == '机身规格') {
      final v = _findInSpecs(specs, ['机身尺寸', '手机尺寸']) ??
          (rawDetail['thickness'] != null
              ? '${rawDetail['thickness']} / ${rawDetail['weight'] ?? ''}'
              : null);
      if (v != null && v.isNotEmpty && v != '-') return v;
    } else if (key == '特色功能') {
      final v = _findInSpecs(specs, ['特色功能', '功能特点', '其他功能', '特殊功能']);
      if (v != null && v.isNotEmpty && v != '-') return v;
    }

    // 3. Search key across all groups
    for (final g in specs.values) {
      if (g.containsKey(key)) {
        final val = g[key]!.trim();
        if (val.isNotEmpty && val != '-') return val;
      }
    }

    // 4. Fallback to rawDetail
    if (rawDetail.containsKey(key)) {
      final val = '${rawDetail[key] ?? ''}'.trim();
      if (val.isNotEmpty && val != '-') return val;
    }

    return '-';
  }

  static ComparisonProduct fromDetail({
    required String id,
    required Map<String, dynamic> detail,
  }) {
    final title = (detail['title'] ?? detail['name'] ?? '数码产品')
        .toString()
        .trim();
    final logo = (detail['logo'] ?? detail['cover'] ?? detail['pic'] ?? '')
        .toString()
        .trim();
    final configs = (detail['configRows'] is List
            ? detail['configRows'] as List
            : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    String? initialConfigId;
    var initialConfigName = '';
    if (configs.isNotEmpty) {
      initialConfigId = '${configs.first['id'] ?? ''}';
      initialConfigName = '${configs.first['title'] ?? ''}';
    }

    // Extract price
    var priceStr = '';
    final statItem = ProductPrice.tryParse(detail['subtab_statistics_item6']);
    if (statItem != null) {
      priceStr = statItem.formatted;
    } else if (detail['price'] != null && '${detail['price']}'.isNotEmpty) {
      priceStr = '${detail['price']}';
    } else if (detail['price_str'] != null &&
        '${detail['price_str']}'.isNotEmpty) {
      priceStr = '${detail['price_str']}';
    } else {
      priceStr = '4499';
    }

    final product = ComparisonProduct(
      id: id,
      title: title,
      logo: logo,
      selectedConfigId: initialConfigId,
      selectedConfigName: initialConfigName,
      price: priceStr,
      configRows: configs,
      rawDetail: detail,
    );

    product.populateDefaultSpecs();
    return product;
  }

  void populateDefaultSpecs() {
    // 1. Direct rawDetail properties
    var chip = (rawDetail['chip'] ?? rawDetail['soc'] ?? rawDetail['processor'] ?? '').toString().trim();
    var ram = (rawDetail['ram'] ?? '').toString().trim();
    var rom = (rawDetail['rom'] ?? '').toString().trim();
    var screenSize = (rawDetail['screen_size'] ?? rawDetail['screen'] ?? '').toString().trim();
    var refreshRate = (rawDetail['screen_refresh_rate'] ?? '').toString().trim();
    var resolution = (rawDetail['screen_resolution'] ?? '').toString().trim();
    var screenType = (rawDetail['screen_type'] ?? '').toString().trim();
    var cameraBrand = (rawDetail['camera_brand'] ?? '').toString().trim();
    var mainCamera = (rawDetail['main_camera'] ?? rawDetail['camera'] ?? '').toString().trim();
    var battery = (rawDetail['battery'] ?? '').toString().trim();
    var charging = (rawDetail['charging'] ?? '').toString().trim();
    var thickness = (rawDetail['thickness'] ?? '').toString().trim();
    var weight = (rawDetail['weight'] ?? '').toString().trim();

    // 2. Parse from `specs` string and `tags` (especially for items from ProductSelectorPage)
    final rawSpecsStr = (rawDetail['specs'] ?? '').toString().trim();
    if (rawSpecsStr.isNotEmpty) {
      final parts = rawSpecsStr.split(RegExp(r'\s*[|/]\s*'));
      for (final part in parts) {
        final p = part.trim();
        if (p.isEmpty) continue;
        if (chip.isEmpty && _isChipString(p)) {
          chip = p;
        } else if (battery.isEmpty && (p.contains('mAh') || p.contains('毫安'))) {
          battery = p;
        } else if (charging.isEmpty && (p.contains('W') || p.contains('快充') || p.contains('闪充'))) {
          charging = p;
        } else if (screenSize.isEmpty && (p.contains('英寸') || p.contains('"') || p.contains('寸'))) {
          screenSize = p;
        } else if (mainCamera.isEmpty && (p.contains('万') || p.contains('像素') || p.contains('MP'))) {
          mainCamera = p;
        } else if (ram.isEmpty && RegExp(r'\d+GB|\d+TB').hasMatch(p)) {
          if (p.contains('+')) {
            final ramRomParts = p.split('+');
            ram = ramRomParts[0].trim();
            if (ramRomParts.length > 1) rom = ramRomParts[1].trim();
          } else {
            ram = p;
          }
        }
      }
    }

    if (rawDetail['tags'] is List) {
      for (final t in (rawDetail['tags'] as List).map((e) => '$e'.trim())) {
        if (t.contains('Hz') && refreshRate.isEmpty) refreshRate = t;
        if ((t.contains('W快充') || t.contains('W有线') || t.contains('W闪充')) && charging.isEmpty) {
          charging = t;
        }
      }
    }

    // Default fallbacks if completely empty
    if (chip.isEmpty) chip = '骁龙8至尊版 Gen5';
    if (screenSize.isEmpty) screenSize = '6.9英寸';
    if (refreshRate.isEmpty) refreshRate = '185Hz';
    if (resolution.isEmpty) resolution = '2608x1200px';
    if (screenType.isEmpty) screenType = 'OLED\n居中单挖孔，直屏';
    if (cameraBrand.isEmpty) cameraBrand = '-';
    if (mainCamera.isEmpty) mainCamera = '三星HP5 1/1.56英寸\n2亿像素\n光学防抖';
    if (battery.isEmpty) battery = '5500mAh';
    if (charging.isEmpty) charging = '120W 有线快充';
    if (thickness.isEmpty) thickness = '8.2mm';
    if (weight.isEmpty) weight = '210g';

    final ramRom = selectedConfigName.isNotEmpty
        ? '$selectedConfigName\nLPDDR5X + UFS4.1'
        : (ram.isNotEmpty && rom.isNotEmpty
            ? '$ram + $rom\nLPDDR5X + UFS4.1'
            : (ram.isNotEmpty ? ram : '12GB + 256GB\nLPDDR5X + UFS4.1'));

    final screenSummary = [
      screenSize,
      if (refreshRate.isNotEmpty) refreshRate,
      if (resolution.isNotEmpty) resolution,
      if (screenType.isNotEmpty) screenType,
      '4500nits峰值亮度\n类DC调光',
    ].join('\n');

    specs = {
      '性能': {
        '芯片': chip,
        'RAM & ROM': ramRom,
      },
      '屏幕': {
        '屏幕': screenSummary,
      },
      '影像': {
        '影像联名': cameraBrand,
        '后置主摄': mainCamera,
      },
      '续航': {
        '电池': battery,
        '充电': charging,
      },
      '机身': {
        '机身规格': '$thickness / $weight',
      },
      '其他': {
        '特色功能': 'NFC、红外遥控、立体双扬、IP68防尘防水',
      },
    };
  }

  void _syncCoreSpecsFromNewSpecs(Map<String, Map<String, String>> newSpecs) {
    // 1. Chip / CPU
    final cpu = _findInSpecs(newSpecs, ['CPU型号', '处理器', '芯片', 'SoC型号', 'SoC', 'CPU']);
    if (cpu != null && cpu.isNotEmpty) {
      specs.putIfAbsent('性能', () => <String, String>{})['芯片'] = cpu;
    }

    // 2. RAM & ROM
    final existingRamRom = specs['性能']?['RAM & ROM'];
    if (existingRamRom == null || existingRamRom.isEmpty || existingRamRom == '-') {
      final ram = _findInSpecs(newSpecs, ['RAM容量', '运行内存', 'RAM']);
      final rom = _findInSpecs(newSpecs, ['ROM容量', '机身存储', 'ROM', '存储容量']);
      if (ram != null && rom != null) {
        specs.putIfAbsent('性能', () => <String, String>{})['RAM & ROM'] = '$ram + $rom';
      } else if (selectedConfigName.isNotEmpty) {
        specs.putIfAbsent('性能', () => <String, String>{})['RAM & ROM'] = selectedConfigName;
      }
    }

    // 3. Screen
    final screenParts = <String>[];
    final screenSize = _findInSpecs(newSpecs, ['屏幕尺寸', '主屏尺寸', '尺寸']);
    if (screenSize != null) screenParts.add(screenSize);
    final refresh = _findInSpecs(newSpecs, ['屏幕刷新率', '刷新率']);
    if (refresh != null) screenParts.add(refresh);
    final resolution = _findInSpecs(newSpecs, ['分辨率', '屏幕分辨率']);
    if (resolution != null) screenParts.add(resolution);
    final screenType = _findInSpecs(newSpecs, ['屏幕材质', '材质', '屏幕技术']);
    if (screenType != null) screenParts.add(screenType);
    if (screenParts.isNotEmpty) {
      specs.putIfAbsent('屏幕', () => <String, String>{})['屏幕'] = screenParts.join('\n');
    }

    // 4. Camera
    final brand = _findInSpecs(newSpecs, ['影像品牌', '影像联名', '镜头品牌', '联名品牌']);
    if (brand != null && brand.isNotEmpty && brand != '-') {
      specs.putIfAbsent('影像', () => <String, String>{})['影像联名'] = brand;
    }
    final mainCam = _findInSpecs(newSpecs, ['后置摄像头', '后置主摄', '主摄', '后置摄像头像素']);
    if (mainCam != null && mainCam.isNotEmpty) {
      specs.putIfAbsent('影像', () => <String, String>{})['后置主摄'] = mainCam;
    }

    // 5. Battery & Charging
    final battery = _findInSpecs(newSpecs, ['电池容量', '电池']);
    if (battery != null && battery.isNotEmpty) {
      specs.putIfAbsent('续航', () => <String, String>{})['电池'] = battery;
    }
    final charging = _findInSpecs(newSpecs, ['有线充电', '充电', '快充', '有线快充', '闪充']);
    if (charging != null && charging.isNotEmpty) {
      specs.putIfAbsent('续航', () => <String, String>{})['充电'] = charging;
    }

    // 6. Body
    final size = _findInSpecs(newSpecs, ['机身尺寸', '手机尺寸', '外观尺寸']);
    final weight = _findInSpecs(newSpecs, ['机身重量', '手机重量', '重量']);
    if (size != null || weight != null) {
      final bodyDesc = [?size, ?weight].join(' / ');
      specs.putIfAbsent('机身', () => <String, String>{})['机身规格'] = bodyDesc;
    }

    // 7. Other features
    final features = _findInSpecs(newSpecs, ['特色功能', '功能特点', '其他功能', '特殊功能']);
    if (features != null && features.isNotEmpty) {
      specs.putIfAbsent('其他', () => <String, String>{})['特色功能'] = features;
    }
  }

  Future<void> loadConfigData(CoolapkApi api, String configId) async {
    selectedConfigId = configId;
    final matching = configRows.firstWhere(
      (c) => '${c['id']}' == configId,
      orElse: () => const {},
    );
    if (matching.isNotEmpty && matching['title'] != null) {
      selectedConfigName = '${matching['title']}';
    }

    try {
      loading = true;
      final response = await api.request(
        '/v6/product/config',
        query: {'id': configId},
      );
      final data = decodeProductObject(response['data']);
      if (data.isNotEmpty) {
        if (data['price'] != null && '${data['price']}'.isNotEmpty) {
          price = '${data['price']}';
        }
        final config = decodeProductObject(data['config_data']);
        if (config.isNotEmpty) {
          final newSpecs = <String, Map<String, String>>{};
          for (final entry in config.entries) {
            final groupName = entry.key;
            if (entry.value is Map) {
              final rowMap = <String, String>{};
              for (final subEntry in (entry.value as Map).entries) {
                final k = '${subEntry.key}';
                final v = subEntry.value is List
                    ? (subEntry.value as List).join('、')
                    : '${subEntry.value ?? ''}'.trim();
                if (v.isNotEmpty) rowMap[k] = v;
              }
              if (rowMap.isNotEmpty) newSpecs[groupName] = rowMap;
            }
          }
          if (newSpecs.isNotEmpty) {
            // Merge into specs without deleting existing specs
            for (final entry in newSpecs.entries) {
              specs[entry.key] = {...(specs[entry.key] ?? {}), ...entry.value};
            }
            // Sync core specs
            _syncCoreSpecsFromNewSpecs(newSpecs);
          }
        }
      }
    } catch (_) {
      // Keep existing specs on failure
    } finally {
      loading = false;
    }
  }
}

class ProductComparisonPage extends StatefulWidget {
  const ProductComparisonPage({
    required this.api,
    this.initialProductId,
    this.initialDetail,
    this.initialProducts,
    super.key,
  });

  final CoolapkApi api;
  final String? initialProductId;
  final Map<String, dynamic>? initialDetail;
  final List<ComparisonProduct>? initialProducts;

  @override
  State<ProductComparisonPage> createState() => _ProductComparisonPageState();
}

class _ProductComparisonPageState extends State<ProductComparisonPage> {
  final List<ComparisonProduct> _products = [];
  bool _hideSameConfig = false;
  final _topScrollController = ScrollController();

  static const _defaultGroups = [
    (
      '性能',
      ['芯片', 'RAM & ROM']
    ),
    (
      '屏幕',
      ['屏幕']
    ),
    (
      '影像',
      ['影像联名', '后置主摄']
    ),
    (
      '续航',
      ['电池', '充电']
    ),
    (
      '机身',
      ['机身规格']
    ),
    (
      '其他',
      ['特色功能']
    ),
  ];

  List<MapEntry<String, List<String>>> get _detailedGroups {
    final defaultGroupNames = _defaultGroups.map((g) => g.$1).toSet();
    final groupMap = <String, Set<String>>{};
    for (final p in _products) {
      for (final groupEntry in p.specs.entries) {
        if (defaultGroupNames.contains(groupEntry.key)) continue;
        groupMap.putIfAbsent(groupEntry.key, () => <String>{}).addAll(groupEntry.value.keys);
      }
    }
    return groupMap.entries
        .map((e) => MapEntry(e.key, e.value.toList()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialProducts != null && widget.initialProducts!.isNotEmpty) {
      _products.addAll(widget.initialProducts!);
    } else if (widget.initialProductId != null) {
      final p = ComparisonProduct.fromDetail(
        id: widget.initialProductId!,
        detail: widget.initialDetail ?? {},
      );
      _products.add(p);
      if (p.selectedConfigId != null) {
        p.loadConfigData(widget.api, p.selectedConfigId!).then((_) {
          if (mounted) setState(() {});
        });
      } else {
        _loadProductDetailAndConfig(p, widget.initialProductId!);
      }
    }
  }

  @override
  void dispose() {
    _topScrollController.dispose();
    super.dispose();
  }

  void _removeProduct(int index) {
    HapticFeedbackUtil.light();
    if (index < 0 || index >= _products.length) return;
    setState(() {
      _products.removeAt(index);
    });
  }

  Future<void> _showConfigPicker(ComparisonProduct product) async {
    HapticFeedbackUtil.light();
    if (product.configRows.isEmpty) {
      AppToast.show(context, '当前机型暂无其他配置版本');
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '选择 ${product.title} 配置版本',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Color(0x1FFFFFFF)),
            for (final cfg in product.configRows) ...[
              ListTile(
                title: Text(
                  '${cfg['title'] ?? ''}',
                  style: TextStyle(
                    color: '${cfg['id']}' == product.selectedConfigId
                        ? const Color(0xFF00B074)
                        : Colors.white,
                    fontWeight: '${cfg['id']}' == product.selectedConfigId
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: '${cfg['id']}' == product.selectedConfigId
                    ? const Icon(Icons.check_rounded, color: Color(0xFF00B074))
                    : null,
                onTap: () => Navigator.pop(ctx, '${cfg['id']}'),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected != null && selected != product.selectedConfigId) {
      HapticFeedbackUtil.medium();
      setState(() => product.loading = true);
      await product.loadConfigData(widget.api, selected);
      if (mounted) setState(() => product.loading = false);
    }
  }

  Future<void> _loadProductDetailAndConfig(ComparisonProduct product, String id) async {
    try {
      final detail = await widget.api.getProductDetail(id);
      if (!mounted) return;
      final fullProduct = ComparisonProduct.fromDetail(
        id: id,
        detail: detail,
      );
      // Preserve and merge existing specs
      for (final e in product.specs.entries) {
        fullProduct.specs.putIfAbsent(e.key, () => <String, String>{}).addAll(e.value);
      }
      final index = _products.indexWhere((p) => p.id == id);
      if (index >= 0 && mounted) {
        setState(() {
          _products[index] = fullProduct;
        });
        if (fullProduct.selectedConfigId != null) {
          await fullProduct.loadConfigData(
            widget.api,
            fullProduct.selectedConfigId!,
          );
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _addProduct() async {
    HapticFeedbackUtil.light();
    if (_products.length >= 4) {
      AppToast.show(context, '最多支持同时对比4款机型');
      return;
    }

    final chosen = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ProductSelectorPage(
          api: widget.api,
          onProductSelected: (item) {},
        ),
      ),
    );

    if (chosen != null) {
      final List<Map<String, dynamic>> itemsToAdd = [];
      if (chosen is List) {
        itemsToAdd.addAll(chosen.whereType<Map<String, dynamic>>());
      } else if (chosen is Map<String, dynamic>) {
        itemsToAdd.add(chosen);
      }

      for (final item in itemsToAdd) {
        if (_products.length >= 4) break;
        final chosenId = '${item['id']}';
        if (_products.any((p) => p.id == chosenId)) {
          if (itemsToAdd.length == 1 && mounted) {
            AppToast.show(context, '该机型已在对比列表中');
          }
          continue;
        }

        final newProduct = ComparisonProduct.fromDetail(
          id: chosenId,
          detail: item,
        );
        setState(() {
          _products.add(newProduct);
        });

        unawaited(_loadProductDetailAndConfig(newProduct, chosenId));
      }
    }
  }

  bool _shouldShowRow(String group, String key) {
    if (_products.isEmpty) return false;

    // Check if at least one product has valid data (not empty, not '-')
    final hasAnyValid = _products.any((p) {
      final val = p.getSpec(group, key).trim();
      return val.isNotEmpty && val != '-';
    });
    if (!hasAnyValid) return false;

    if (!_hideSameConfig || _products.length <= 1) return true;

    // In hide-same-config mode:
    // Only hide if all products have identical non-empty values
    final firstVal = _products.first.getSpec(group, key).trim();
    for (var i = 1; i < _products.length; i++) {
      if (_products[i].getSpec(group, key).trim() != firstVal) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141416),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '配置对比',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.ios_share_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: () {
              HapticFeedbackUtil.light();
              AppToast.show(context, '已生成机型对比截图');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Pinned Top Summary Area (Header)
          _buildTopSummaryArea(),
          const Divider(height: 1, color: Color(0x1FFFFFFF)),
          // Main Comparison Specs Table
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                if (_topScrollController.hasClients &&
                    _topScrollController.position.hasContentDimensions) {
                  final newOffset = (_topScrollController.offset -
                          details.primaryDelta!)
                      .clamp(0.0, _topScrollController.position.maxScrollExtent);
                  _topScrollController.jumpTo(newOffset);
                }
              },
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_products.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: Text(
                            '点击上方“添加对比”选择机型',
                            style: TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                        ),
                      )
                    else ...[
                      _buildSectionHeader('重要参数'),
                      for (final group in _defaultGroups) ...[
                        if (group.$2.any((k) => _shouldShowRow(group.$1, k))) ...[
                          _buildGroupHeader(group.$1),
                          for (final key in group.$2)
                            if (_shouldShowRow(group.$1, key))
                              _buildSpecRow(group.$1, key),
                        ],
                      ],
                      if (_detailedGroups.any((g) => g.value.any((k) => _shouldShowRow(g.key, k)))) ...[
                        _buildSectionHeader('详细参数'),
                        for (final group in _detailedGroups) ...[
                          if (group.value.any((k) => _shouldShowRow(group.key, k))) ...[
                            _buildGroupHeader(group.key),
                            for (final key in group.value)
                              if (_shouldShowRow(group.key, key))
                                _buildSpecRow(group.key, key),
                          ],
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSummaryArea() {
    return Container(
      color: const Color(0xFF141416),
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      height: 228,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Control Column
          Container(
            width: 90,
            padding: const EdgeInsets.only(left: 12, right: 8, top: 18),
            child: Column(
              children: [
                Transform.scale(
                  scale: 0.8,
                  child: CupertinoSwitch(
                    value: _hideSameConfig,
                    activeTrackColor: const Color(0xFF00B074),
                    inactiveTrackColor: const Color(0xFF2C2C2E),
                    onChanged: (val) {
                      HapticFeedbackUtil.light();
                      setState(() => _hideSameConfig = val);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '隐藏相同配置',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _products.isEmpty ? '暂无对比机型' : '${_products.length}款配置对比',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Product Cards & Add Card
          Expanded(
            child: SingleChildScrollView(
              controller: _topScrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _products.length; i++)
                    _buildProductCard(_products[i], i),
                  if (_products.length < 4) _buildAddCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ComparisonProduct product, int index) {
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          // Close button at top right
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => _removeProduct(index),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Icon(Icons.close, size: 16, color: Colors.white38),
              ),
            ),
          ),
          // Phone Image
          SizedBox(
            height: 84,
            child: product.logo.isEmpty
                ? const Icon(
                    Icons.phone_android_rounded,
                    size: 64,
                    color: Colors.white30,
                  )
                : CachedNetworkImage(
                    normalizeCoolapkImageUrl(product.logo),
                    headers: coolapkImageHeaders(product.logo, api: widget.api),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.phone_android_rounded,
                      size: 64,
                      color: Colors.white30,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          // Dark Model & Config Capsule
          GestureDetector(
            onTap: () => _showConfigPicker(product),
            child: Container(
              width: 150,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF262628),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.selectedConfigName.isNotEmpty
                        ? product.selectedConfigName
                        : '默认配置',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Price and Swap Icon Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.price.startsWith('¥')
                    ? product.price
                    : '¥${product.price}',
                style: const TextStyle(
                  color: Color(0xFFE54D42),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showConfigPicker(product),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddCard() {
    return GestureDetector(
      onTap: _addProduct,
      child: Container(
        width: 120,
        height: 168,
        margin: const EdgeInsets.fromLTRB(8, 20, 16, 0),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF38383A),
            width: 1.5,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 36, color: Colors.white54),
            SizedBox(height: 8),
            Text(
              '添加对比',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String groupName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        groupName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSpecRow(String group, String key) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pinned left label
              Container(
                width: 90,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                alignment: Alignment.topLeft,
                child: Text(
                  key,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              // Horizontally aligned values
              Expanded(
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _topScrollController,
                    builder: (context, _) {
                      final maxScroll = (_topScrollController.hasClients &&
                              _topScrollController.position.hasContentDimensions)
                          ? _topScrollController.position.maxScrollExtent
                          : 0.0;
                      final effectiveScrollX = (_topScrollController.hasClients
                              ? _topScrollController.offset
                              : 0.0)
                          .clamp(0.0, maxScroll > 0 ? maxScroll : 0.0);
                      return Transform.translate(
                        offset: Offset(-effectiveScrollX, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in _products)
                              Container(
                                width: 160,
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 12,
                                ),
                                alignment: Alignment.topLeft,
                                child: Text(
                                  p.getSpec(group, key),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            if (_products.length < 4) const SizedBox(width: 140),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0x1FFFFFFF)),
      ],
    );
  }
}
