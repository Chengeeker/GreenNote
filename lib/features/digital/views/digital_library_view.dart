import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_card.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/network/coolapk_image.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/cached_network_image.dart';
import '../../../core/widgets/review_refresh_header.dart';
import '../../shared/api_list_page.dart';
import 'digital_brand_page.dart';
import '../widgets/digital_cards.dart';

enum DigitalLibrarySort { hot, score, newest }

const _digitalLibraryDarkCategoryBackground = Color(0xFF1C1C1E);
const _digitalLibraryDarkSubcategoryBackground = Color(0xFF101010);

class DigitalLibraryView extends StatefulWidget {
  const DigitalLibraryView({
    required this.api,
    this.initialCategoryId = '1000',
    this.selectionRevision = 0,
    this.showCategoryRail = true,
    this.tabletPresentation = false,
    super.key,
  });

  final CoolapkApi api;
  final String initialCategoryId;
  final int selectionRevision;
  final bool showCategoryRail;
  final bool tabletPresentation;

  @override
  State<DigitalLibraryView> createState() => _DigitalLibraryViewState();
}

class _DigitalLibraryViewState extends State<DigitalLibraryView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // 14 个官方分类定义 (含官方真实 endpoint URL)
  static const List<Map<String, dynamic>> _defaultCategories = [
    {
      'id': '0',
      'title': '热门',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D0%26showMode%3D0',
    },
    {
      'id': '1000',
      'title': '手机',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1000%26showMode%3D0',
    },
    {
      'id': '1001',
      'title': '平板',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1001%26showMode%3D0',
    },
    {
      'id': '1037',
      'title': '耳机',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1037%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1052',
          'title': '无线耳机',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1052%26showMode%3D0',
        },
        {
          'id': '1053',
          'title': '有线耳机',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1053%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1005',
      'title': '穿戴设备',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1005%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1041',
          'title': '智能手表',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1041%26showMode%3D0',
        },
        {
          'id': '1042',
          'title': '智能手环',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1042%26showMode%3D0',
        },
        {
          'id': '1043',
          'title': 'VR/AR',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1043%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1006',
      'title': '数码配件',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1006%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1044',
          'title': '移动电源',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1044%26showMode%3D0',
        },
        {
          'id': '1045',
          'title': '充电器',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1045%26showMode%3D0',
        },
        {
          'id': '1046',
          'title': '数据线',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1046%26showMode%3D0',
        },
        {
          'id': '1047',
          'title': '保护周边',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1047%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1038',
      'title': '电脑·外设',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1038%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1054',
          'title': '笔记本',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1054%26showMode%3D0',
        },
        {
          'id': '1055',
          'title': '键盘',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1055%26showMode%3D0',
        },
        {
          'id': '1056',
          'title': '鼠标',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1056%26showMode%3D0',
        },
        {
          'id': '1057',
          'title': '显示器',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1057%26showMode%3D0',
        },
        {
          'id': '1058',
          'title': '电脑硬件',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1058%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1004',
      'title': '智能家居',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1004%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1048',
          'title': '路由器',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1048%26showMode%3D0',
        },
        {
          'id': '1049',
          'title': '智能音箱',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1049%26showMode%3D0',
        },
        {
          'id': '1050',
          'title': '生活家电',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1050%26showMode%3D0',
        },
        {
          'id': '1051',
          'title': '安防监控',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1051%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1039',
      'title': '游戏',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1039%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1059',
          'title': '游戏主机',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1059%26showMode%3D0',
        },
        {
          'id': '1060',
          'title': '掌机',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1060%26showMode%3D0',
        },
        {
          'id': '1061',
          'title': '游戏手柄',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1061%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1011',
      'title': '汽车',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1011%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1062',
          'title': '新能源车',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1062%26showMode%3D0',
        },
        {
          'id': '1063',
          'title': '燃油车',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1063%26showMode%3D0',
        },
        {
          'id': '1064',
          'title': '车载用品',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1064%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1040',
      'title': '摄影',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1040%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1065',
          'title': '微单/单反',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1065%26showMode%3D0',
        },
        {
          'id': '1066',
          'title': '相机镜头',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1066%26showMode%3D0',
        },
        {
          'id': '1067',
          'title': '运动相机',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1067%26showMode%3D0',
        },
        {
          'id': '1068',
          'title': '无人机/云台',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1068%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1015',
      'title': '电动车',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1015%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1069',
          'title': '电动两轮车',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1069%26showMode%3D0',
        },
        {
          'id': '1070',
          'title': '电动滑板车',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1070%26showMode%3D0',
        },
        {
          'id': '1071',
          'title': '骑行配件',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1071%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1009',
      'title': '其他',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1009%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1072',
          'title': '办公设备',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1072%26showMode%3D0',
        },
        {
          'id': '1073',
          'title': '奇趣数码',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1073%26showMode%3D0',
        },
      ],
    },
    {
      'id': '1083',
      'title': '运动装备',
      'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1083%26showMode%3D0',
      'secondCategoryRows': [
        {
          'id': '1084',
          'title': '跑步运动',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1084%26showMode%3D0',
        },
        {
          'id': '1085',
          'title': '户外出行',
          'url': '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D1085%26showMode%3D0',
        },
      ],
    },
  ];

  // 默认兜底品牌数据
  static const List<Map<String, String>> _defaultBrands = [
    {
      'name': '小米',
      'logo': 'http://image.coolapk.com/product_logo/2025/0427/16/0_3140_2957_310@1000x500.png',
      'id': '1016',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1016%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '华为',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_8718_7917@182x90.jpg',
      'id': '1002',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1002%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '荣耀',
      'logo': 'https://img.coolapk.com/picture/2021/0122/10/1032338_1611283624_5739.png',
      'id': '1007',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1007%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': 'vivo',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_9017_754@160x80.jpg',
      'id': '1001',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1001%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': 'OPPO',
      'logo': 'http://image.coolapk.com/product_logo/2026/0403/14/0_9499_7941_208@580x326.jpg',
      'id': '1000',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1000%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '三星',
      'logo': 'https://img.coolapk.com/picture/2021/0401/17/1032338_1617269476_2894.png',
      'id': '1003',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1003%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': 'realme',
      'logo': 'https://img.coolapk.com/picture/2021/0401/17/1032338_1617269382_1688.png',
      'id': '1035',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1035%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': 'iQOO',
      'logo': 'https://img.coolapk.com/picture/2021/0401/17/1032338_1617269601_3879.png',
      'id': '1036',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1036%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '一加',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_6008_4842@160x80.jpg',
      'id': '1004',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1004%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '魅族',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_2097_6822@160x80.jpg',
      'id': '1005',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1005%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '苹果',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_4210_512@160x80.jpg',
      'id': '1008',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1008%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '红米',
      'logo': 'https://img.coolapk.com/picture/2021/0401/17/1032338_1617269527_5239.png',
      'id': '1037',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1037%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '摩托罗拉',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_7890_1234@160x80.jpg',
      'id': '1010',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1010%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '中兴',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_4567_8901@160x80.jpg',
      'id': '1012',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1012%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '索尼',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_1234_5678@160x80.jpg',
      'id': '1013',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1013%26category_id%3D1000%26showMode%3D0',
    },
    {
      'name': '努比亚',
      'logo': 'http://image.coolapk.com/product_logo/2019/1226/10/0_5678_1234@160x80.jpg',
      'id': '1014',
      'url': '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D1014%26category_id%3D1000%26showMode%3D0',
    },
  ];

  List<Map<String, dynamic>> _categories = List.from(_defaultCategories);
  late Map<String, dynamic> _selectedCategory;

  List<Map<String, String>> _brands = List.from(_defaultBrands);
  String? _tabletBrandError;
  String? _selectedBrand;

  final Map<DigitalLibrarySort, String> _sortUrls = {};
  DigitalLibrarySort _sort = DigitalLibrarySort.hot;

  final Set<String> _followedProductIds = {};
  final Set<String> _expandedCategoryIds = {};

  bool _loading = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    if (widget.tabletPresentation) {
      _brands = [];
      _loadTabletBrands();
    }
    _selectInitialCategory();
    _initCategoryList();
    _loadProducts(refresh: true);
  }

  @override
  void didUpdateWidget(covariant DigitalLibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategoryId != widget.initialCategoryId ||
        oldWidget.selectionRevision != widget.selectionRevision) {
      _selectInitialCategory();
      _selectedBrand = null;
      _sort = DigitalLibrarySort.hot;
      _sortUrls.clear();
      _loadProducts(refresh: true);
    }
  }

  void _selectInitialCategory() {
    // 智能定位初始分类（支持二级分类与自动展开对应父级）
    _expandedCategoryIds.clear();
    Map<String, dynamic>? initialMatch;
    for (final cat in _categories) {
      final rawChildren =
          cat['secondCategoryRows'] ?? cat['subCategories'] ?? cat['children'];
      if (rawChildren is List) {
        for (final c in rawChildren) {
          if (c is Map &&
              (c['id'] ?? '').toString() == widget.initialCategoryId) {
            _expandedCategoryIds.add((cat['id'] ?? '').toString());
            initialMatch = Map<String, dynamic>.from(c);
            break;
          }
        }
      }
      if (initialMatch != null) break;
      if ((cat['id'] ?? '').toString() == widget.initialCategoryId) {
        if (rawChildren is List && rawChildren.isNotEmpty) {
          _expandedCategoryIds.add(widget.initialCategoryId);
          initialMatch = Map<String, dynamic>.from(rawChildren.first as Map);
        } else {
          initialMatch = cat;
        }
        break;
      }
    }
    _selectedCategory =
        initialMatch ??
        _categories.firstWhere(
          (category) => category['id'].toString() == widget.initialCategoryId,
          orElse: () => _categories[1],
        );
  }

  Future<void> _loadTabletBrands() async {
    try {
      final page = await widget.api.getList('/v6/product/brandList');
      final rows = <Map<String, dynamic>>[];
      for (final item in page.items) {
        final nested = item['entities'];
        if ((item['entityType'] ?? '').toString().toLowerCase() == 'card' &&
            nested is List) {
          rows.addAll(nested.whereType<Map>().map(Map<String, dynamic>.from));
        } else {
          rows.add(item);
        }
      }
      final brands = rows
          .map((item) {
            final name = (item['title'] ?? item['name'] ?? '').toString();
            final logo = (item['logo'] ?? item['pic'] ?? item['icon'] ?? '')
                .toString();
            final id = (item['id'] ?? item['entityId'] ?? '').toString();
            final serverUrl = (item['url'] ?? '').toString();
            final url = serverUrl.isNotEmpty
                ? serverUrl
                      .replaceAll(
                        RegExp(r'category_id%3D\d+'),
                        'category_id%3D1001',
                      )
                      .replaceAll(
                        RegExp(r'category_id=\d+'),
                        'category_id=1001',
                      )
                : id.isEmpty
                ? ''
                : '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D$id%26category_id%3D1001%26showMode%3D0';
            return <String, String>{
              'name': name,
              'logo': logo,
              'id': id,
              'url': url,
            };
          })
          .where(
            (brand) => brand['name']!.isNotEmpty && brand['url']!.isNotEmpty,
          )
          .toList(growable: false);
      if (mounted && _brands.isEmpty && brands.isNotEmpty) {
        setState(() {
          _brands = brands;
          _tabletBrandError = null;
        });
      }
    } catch (error) {
      if (mounted && _brands.isEmpty) {
        setState(() => _tabletBrandError = error.toString());
      }
    }
  }

  // 1. 动态加载官方全量分类列表（深度解析并保留二级分类）
  Future<void> _initCategoryList() async {
    try {
      final res = await widget.api.request('/v6/product/categoryList');
      if (!mounted) return;
      final data = res['data'];
      if (data is List && data.isNotEmpty) {
        final List<Map<String, dynamic>> loaded = [];
        for (final item in data) {
          if (item is Map) {
            final cat = Map<String, dynamic>.from(item);
            final rawSubs =
                cat['secondCategoryRows'] ??
                cat['subCategories'] ??
                cat['children'];
            if (rawSubs is List && rawSubs.isNotEmpty) {
              cat['secondCategoryRows'] = rawSubs
                  .whereType<Map>()
                  .map((s) => Map<String, dynamic>.from(s))
                  .toList();
            }
            loaded.add(cat);
          }
        }
        if (loaded.isNotEmpty) {
          setState(() {
            _categories = loaded;
            // 保持当前选中的分类同步（大类或二级子分类）
            final currentId = (_selectedCategory['id'] ?? '').toString();
            Map<String, dynamic>? match;
            for (final cat in loaded) {
              if ((cat['id'] ?? '').toString() == currentId) {
                match = cat;
                break;
              }
              final subs = cat['secondCategoryRows'];
              if (subs is List) {
                for (final sub in subs) {
                  if (sub is Map && (sub['id'] ?? '').toString() == currentId) {
                    match = Map<String, dynamic>.from(sub);
                    _expandedCategoryIds.add((cat['id'] ?? '').toString());
                    break;
                  }
                }
              }
              if (match != null) break;
            }
            _selectedCategory =
                match ?? (loaded.length > 1 ? loaded[1] : loaded.first);
          });
        }
      }
    } catch (_) {
      // 保持 defaultCategories 兜底
    }
  }

  // 2. 根据当前分类与排序规则计算目标 URL
  String _computeTargetUrl() {
    if (_sortUrls.containsKey(_sort) && _sortUrls[_sort]!.isNotEmpty) {
      return _sortUrls[_sort]!;
    }

    final baseUrl = (_selectedCategory['url'] ?? '').toString();
    if (baseUrl.isEmpty) {
      final catId = (_selectedCategory['id'] ?? '1000').toString();
      return '/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D$catId%26showMode%3D0';
    }

    if (_sort == DigitalLibrarySort.hot) {
      return baseUrl;
    }

    // 注入排序字段
    final sortParam = _sort == DigitalLibrarySort.score
        ? 'sortField%3Downer_star_average_score%26limitField%3Downer_star_total_count-80'
        : 'sortField%3Drelease_time';

    if (baseUrl.contains('sortField')) {
      return baseUrl.replaceAll(
        RegExp(r'sortField%3D[^%&]+'),
        _sort == DigitalLibrarySort.score
            ? 'sortField%3Downer_star_average_score'
            : 'sortField%3Drelease_time',
      );
    }

    return '$baseUrl%26$sortParam';
  }

  // 3. 核心产品列表请求与聚合卡片解析
  Future<void> _loadProducts({required bool refresh}) async {
    if (_loading) return;

    final requestedCategoryId = (_selectedCategory['id'] ?? '').toString();

    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final targetUrl = _computeTargetUrl();
      final res = await widget.api.request(
        '/v6/page/dataList',
        query: {'url': targetUrl, 'page': _page},
      );

      if (!mounted) return;
      if (requestedCategoryId != (_selectedCategory['id'] ?? '').toString()) {
        setState(() => _loading = false);
        _loadProducts(refresh: true);
        return;
      }
      final data = res['data'];

      final List<Map<String, dynamic>> newProducts = [];
      final List<Map<String, String>> dynamicBrands = [];

      if (data is List) {
        for (final item in data) {
          if (item is! Map) continue;
          final entity = Map<String, dynamic>.from(item);
          final entityType = (entity['entityType'] ?? '').toString();
          final template = (entity['entityTemplate'] ?? '').toString();
          final title = (entity['title'] ?? '').toString();

          // 解析品牌卡片
          if (entityType == 'card' &&
              (template == 'brandList' || title == '品牌')) {
            final entities = entity['entities'];
            if (entities is List) {
              for (final b in entities) {
                if (b is Map) {
                  final bMap = Map<String, dynamic>.from(b);
                  final bName = (bMap['title'] ?? bMap['name'] ?? '')
                      .toString();
                  final bLogo = (bMap['logo'] ?? bMap['pic'] ?? '').toString();
                  var bUrl = (bMap['url'] ?? '').toString();
                  final bId = (bMap['id'] ?? bMap['entityId'] ?? '').toString();
                  if (widget.tabletPresentation) {
                    bUrl = bUrl
                        .replaceAll(
                          RegExp(r'category_id%3D\d+'),
                          'category_id%3D1001',
                        )
                        .replaceAll(
                          RegExp(r'category_id=\d+'),
                          'category_id=1001',
                        );
                    if (bUrl.isEmpty && bId.isNotEmpty) {
                      bUrl =
                          '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D$bId%26category_id%3D1001%26showMode%3D0';
                    }
                  }
                  if (bName.isNotEmpty) {
                    dynamicBrands.add({
                      'name': bName,
                      'logo': bLogo,
                      'url': bUrl,
                      'id': bId,
                    });
                  }
                }
              }
            }
          }
          // 解析排序卡片
          else if (entityType == 'card' &&
              (template == 'sortSelectCard' || title == '排序规则')) {
            final entities = entity['entities'];
            if (entities is List) {
              for (final s in entities) {
                if (s is Map) {
                  final sTitle = (s['title'] ?? '').toString();
                  final sUrl = (s['url'] ?? '').toString();
                  if (sTitle == '热度') {
                    _sortUrls[DigitalLibrarySort.hot] = sUrl;
                  } else if (sTitle == '评分') {
                    _sortUrls[DigitalLibrarySort.score] = sUrl;
                  } else if (sTitle == '最新') {
                    _sortUrls[DigitalLibrarySort.newest] = sUrl;
                  }
                }
              }
            }
          }
          // 解析数码产品
          else if (entityType == 'product' ||
              (entity.containsKey('id') && entity.containsKey('title'))) {
            newProducts.add(entity);
            // 同步服务端初始关注状态
            final isFollow = entity['is_follow'];
            final id = (entity['id'] ?? entity['entityId'] ?? '').toString();
            if (id.isNotEmpty && (isFollow == 1 || isFollow == '1')) {
              _followedProductIds.add(id);
            }
          }
        }
      }

      setState(() {
        if (dynamicBrands.isNotEmpty) {
          _brands = dynamicBrands;
          _tabletBrandError = null;
        }

        if (refresh) {
          _products = newProducts;
        } else {
          _products.addAll(newProducts);
        }

        if (newProducts.isEmpty || newProducts.length < 10) {
          _hasMore = false;
        } else {
          _page++;
        }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (requestedCategoryId != (_selectedCategory['id'] ?? '').toString()) {
        setState(() => _loading = false);
        _loadProducts(refresh: true);
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // 4. 品牌进入独立系列页，父级分类产品列表保持原样
  void _selectBrand(Map<String, String> brand) {
    final brandName = brand['name'] ?? '';
    final brandId = brand['id'] ?? '';
    final categoryId = (_selectedCategory['id'] ?? '1000').toString();
    final brandUrl = (brand['url'] ?? '').isNotEmpty
        ? brand['url']!
        : brandId.isEmpty
        ? ''
        : '/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D$brandId%26category_id%3D$categoryId%26showMode%3D0';
    if (brandName.isEmpty || brandUrl.isEmpty) return;

    HapticFeedbackUtil.selection();
    setState(() => _selectedBrand = brandName);

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            DigitalBrandPage(api: widget.api, title: brandName, url: brandUrl),
      ),
    );
  }

  // 5. 排序规则切换
  void _selectSort(DigitalLibrarySort sort) {
    if (_sort == sort) return;
    HapticFeedbackUtil.selection();
    setState(() {
      _sort = sort;
    });
    _loadProducts(refresh: true);
  }

  // 6. 真实关注动作交互与接口调用
  Future<void> _toggleFollow(String id, String title) async {
    HapticFeedbackUtil.light();
    if (!widget.api.hasCookie) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('关注设备需要先登录酷安账号'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final isFollowed = _followedProductIds.contains(id);
    final newStatus = isFollowed ? 0 : 1;

    // 乐观更新 UI
    setState(() {
      if (isFollowed) {
        _followedProductIds.remove(id);
      } else {
        _followedProductIds.add(id);
      }
    });

    try {
      await widget.api.request(
        '/v6/product/changeFollowStatus',
        method: 'POST',
        body: {'id': id, 'status': '$newStatus'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus == 1 ? '已关注 $title' : '已取消关注 $title'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // 失败回滚状态
      setState(() {
        if (isFollowed) {
          _followedProductIds.add(id);
        } else {
          _followedProductIds.remove(id);
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  // 7. 长按查看设备参数配置
  void _showProductSpecs(BuildContext context, Map<String, dynamic> p) {
    HapticFeedbackUtil.medium();
    final theme = Theme.of(context);
    final title = (p['title'] ?? p['name'] ?? '数码机型').toString();
    final pic = (p['logo'] ?? p['pic'] ?? p['cover'] ?? '').toString();
    final tagArr = p['tagArr'];
    final List<String> tags = [];
    if (tagArr is List) {
      for (final t in tagArr) {
        if (t != null && t.toString().trim().isNotEmpty) {
          tags.add(t.toString().trim());
        }
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            24 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (pic.isNotEmpty)
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: CachedNetworkImage(
                        normalizeCoolapkImageUrl(pic),
                        headers: coolapkImageHeaders(pic, api: widget.api),
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '热度: ${p['hot_num_txt'] ?? p['hot'] ?? '未知'} · 评分: ${p['star_average_score'] ?? p['score'] ?? '暂无'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '参数规格',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (tags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                )
              else
                Text(
                  '暂无详细参数',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    final id = (p['id'] ?? p['entityId'] ?? '').toString();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductPage(
                          api: widget.api,
                          id: id,
                          title: title.replaceAll('\n', ' '),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('查看机主评价与动态'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryRailTile(
    BuildContext context,
    Map<String, dynamic> cat,
    ColorScheme colorScheme,
    Color primaryGreen,
    ThemeData theme,
  ) {
    final catId = (cat['id'] ?? '').toString();
    final title = (cat['title'] ?? '分类').toString();
    final rawChildren =
        cat['secondCategoryRows'] ?? cat['subCategories'] ?? cat['children'];
    final List<Map<String, dynamic>> children = [];
    if (rawChildren is List) {
      for (final c in rawChildren) {
        if (c is Map) {
          children.add(Map<String, dynamic>.from(c));
        }
      }
    }
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedCategoryIds.contains(catId);
    final isSelectedParent =
        (_selectedCategory['id'] ?? '').toString() == catId;
    final hasSelectedChild = children.any(
      (c) =>
          (c['id'] ?? '').toString() ==
          (_selectedCategory['id'] ?? '').toString(),
    );
    final categoryBackground = theme.brightness == Brightness.dark
        ? _digitalLibraryDarkCategoryBackground
        : colorScheme.surfaceContainerLow;
    final subcategoryBackground = theme.brightness == Brightness.dark
        ? _digitalLibraryDarkSubcategoryBackground
        : colorScheme.surface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            HapticFeedbackUtil.selection();
            if (hasChildren) {
              setState(() {
                if (isExpanded) {
                  _expandedCategoryIds.remove(catId);
                } else {
                  _expandedCategoryIds.add(catId);
                  if (!hasSelectedChild) {
                    _selectedCategory = children.first;
                    _selectedBrand = null;
                    _sort = DigitalLibrarySort.hot;
                    _sortUrls.clear();
                    _loadProducts(refresh: true);
                  }
                }
              });
            } else {
              if (isSelectedParent) return;
              setState(() {
                _selectedCategory = cat;
                _selectedBrand = null;
                _sort = DigitalLibrarySort.hot;
                _sortUrls.clear();
              });
              _loadProducts(refresh: true);
            }
          },
          child: Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: (isSelectedParent && !hasChildren)
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                  : categoryBackground,
              border: (isSelectedParent && !hasChildren)
                  ? Border(left: BorderSide(color: primaryGreen, width: 3.5))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: (isSelectedParent || hasSelectedChild)
                          ? 14.5
                          : 13.5,
                      fontWeight: (isSelectedParent || hasSelectedChild)
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: (isSelectedParent && !hasChildren)
                          ? primaryGreen
                          : (hasSelectedChild
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded) ...[
          for (final child in children) ...[
            Builder(
              builder: (context) {
                final childId = (child['id'] ?? '').toString();
                final isChildSelected =
                    (_selectedCategory['id'] ?? '').toString() == childId;
                final childTitle = (child['title'] ?? child['name'] ?? '子分类')
                    .toString();

                return InkWell(
                  onTap: () {
                    if (isChildSelected) return;
                    HapticFeedbackUtil.selection();
                    setState(() {
                      _selectedCategory = child;
                      _selectedBrand = null;
                      _sort = DigitalLibrarySort.hot;
                      _sortUrls.clear();
                    });
                    _loadProducts(refresh: true);
                  },
                  child: Container(
                    height: 42,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 18, right: 10),
                    decoration: BoxDecoration(
                      color: isChildSelected
                          ? (theme.brightness == Brightness.dark
                                ? const Color(0xFF003830)
                                : primaryGreen.withValues(alpha: 0.12))
                          : subcategoryBackground,
                      border: isChildSelected
                          ? Border(
                              left: BorderSide(color: primaryGreen, width: 3.5),
                            )
                          : null,
                    ),
                    child: Text(
                      childTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isChildSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isChildSelected
                            ? primaryGreen
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryGreen = const Color(0xFF00B074);
    if (widget.tabletPresentation) return _buildTablet(context, primaryGreen);
    final isHotCategory =
        (_selectedCategory['id'] ?? '').toString() == '0' ||
        (_selectedCategory['title'] ?? '').toString() == '热门';

    return Row(
      children: [
        // 1. 左侧纵向纯文本分类轨道（支持二级子分类展开与折叠）
        if (widget.showCategoryRail)
          SizedBox(
            width: 100,
            child: Container(
              color: theme.brightness == Brightness.dark
                  ? _digitalLibraryDarkCategoryBackground
                  : colorScheme.surfaceContainerLow,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final cat in _categories)
                    _buildCategoryRailTile(
                      context,
                      cat,
                      colorScheme,
                      primaryGreen,
                      theme,
                    ),
                ],
              ),
            ),
          ),
        if (widget.showCategoryRail)
          const VerticalDivider(width: 1, thickness: 0.5),

        // 2. 右侧内容区域 (真实品牌专区 + 排序规则 + 3 列真实产品流)
        Expanded(
          child: EasyRefresh(
            header: reviewDefaultRefreshHeader,
            onRefresh: () async => _loadProducts(refresh: true),
            onLoad: _hasMore ? () async => _loadProducts(refresh: false) : null,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                8,
                10,
                12,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                if (!isHotCategory) ...[
                  // 2.1 品牌 Header 与横向品牌卡片网格
                  Row(
                    children: [
                      Text(
                        '品牌',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (_selectedBrand != null)
                        GestureDetector(
                          onTap: () {
                            HapticFeedbackUtil.selection();
                            setState(() {
                              _selectedBrand = null;
                            });
                          },
                          child: Text(
                            '重置品牌',
                            style: TextStyle(fontSize: 12, color: primaryGreen),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 品牌 2 行横向左右可滑动列表（支持全量品牌无上限展示）
                  SizedBox(
                    height: 126,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      itemCount: (_brands.length + 1) ~/ 2,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, colIndex) {
                        final topIndex = colIndex * 2;
                        final bottomIndex = colIndex * 2 + 1;
                        final topBrand = _brands[topIndex];
                        final bottomBrand = bottomIndex < _brands.length
                            ? _brands[bottomIndex]
                            : null;

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildBrandItem(context, topBrand, primaryGreen),
                            const SizedBox(height: 8),
                            if (bottomBrand != null)
                              _buildBrandItem(
                                context,
                                bottomBrand,
                                primaryGreen,
                              )
                            else
                              const SizedBox(width: 66, height: 58),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2.2 排序规则 (热度 / 评分 / 最新)
                  Row(
                    children: [
                      Text(
                        '排序规则',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      _SortChip(
                        label: '热度',
                        selected: _sort == DigitalLibrarySort.hot,
                        onTap: () => _selectSort(DigitalLibrarySort.hot),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: '评分',
                        selected: _sort == DigitalLibrarySort.score,
                        onTap: () => _selectSort(DigitalLibrarySort.score),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: '最新',
                        selected: _sort == DigitalLibrarySort.newest,
                        onTap: () => _selectSort(DigitalLibrarySort.newest),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                ],

                // 2.3 3 列产品网格
                if (_loading && _products.isEmpty)
                  const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_products.isEmpty)
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.devices_other_rounded,
                            size: 48,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error != null ? '加载失败: $_error' : '暂无产品数据',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () => _loadProducts(refresh: true),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.44,
                        ),
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final p = _products[index];
                      final id =
                          (p['id'] ??
                                  p['productId'] ??
                                  p['entityId'] ??
                                  'p_$index')
                              .toString();
                      final title = (p['title'] ?? p['name'] ?? '数码机型')
                          .toString();
                      final pic =
                          (p['logo'] ??
                                  p['pic'] ??
                                  p['cover'] ??
                                  p['thumb'] ??
                                  '')
                              .toString();
                      final hot =
                          (p['hot_num_txt'] ?? p['hot'] ?? p['hot_num'] ?? '')
                              .toString();
                      final score =
                          (p['star_average_score'] ??
                                  p['score'] ??
                                  p['recent_30_days_owner_star_average_score'] ??
                                  '')
                              .toString();

                      final isFollowed = _followedProductIds.contains(id);

                      return GestureDetector(
                        onTap: () {
                          HapticFeedbackUtil.selection();
                          // 点击直达官方产品详情与机主动态页
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ProductPage(
                                api: widget.api,
                                id: id,
                                title: title.replaceAll('\n', ' '),
                              ),
                            ),
                          );
                        },
                        onLongPress: () => _showProductSpecs(context, p),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh.withValues(
                              alpha: 0.7,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 产品图
                              SizedBox(
                                height: 68,
                                child: Center(
                                  child: pic.isNotEmpty
                                      ? CachedNetworkImage(
                                          normalizeCoolapkImageUrl(pic),
                                          headers: coolapkImageHeaders(
                                            pic,
                                            api: widget.api,
                                          ),
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, _, _) => Icon(
                                            Icons.phone_android_rounded,
                                            size: 40,
                                            color: colorScheme.outline,
                                          ),
                                        )
                                      : Icon(
                                          Icons.phone_android_rounded,
                                          size: 40,
                                          color: colorScheme.outline,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),

                              // 机型标题
                              SizedBox(
                                height: 32,
                                child: Center(
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),

                              // 热度或评分
                              if (_sort == DigitalLibrarySort.score &&
                                  score.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 13,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      score,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      '🔥',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      formatDigitalHot(
                                        hot.isEmpty ? '100.0万' : hot,
                                      ),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),

                              const Spacer(),

                              // 绿色胶囊关注按钮
                              GestureDetector(
                                onTap: () => _toggleFollow(id, title),
                                child: Container(
                                  width: double.infinity,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isFollowed
                                        ? colorScheme.surfaceContainerHighest
                                        : primaryGreen,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    isFollowed ? '已关注' : '关注',
                                    style: TextStyle(
                                      color: isFollowed
                                          ? colorScheme.onSurfaceVariant
                                          : Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTablet(BuildContext context, Color primaryGreen) {
    return EasyRefresh(
      header: reviewDefaultRefreshHeader,
      onRefresh: () async => _loadProducts(refresh: true),
      onLoad: _hasMore ? () async => _loadProducts(refresh: false) : null,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          10,
          8,
          10,
          100 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          ReviewCard(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日热门', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (_loading && _products.isEmpty)
                    const SizedBox(
                      height: 140,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_products.isEmpty)
                    _tabletEmpty(context)
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisExtent: 132,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _products.length > 8 ? 8 : _products.length,
                      itemBuilder: (context, index) =>
                          _tabletHotItem(context, index),
                    ),
                ],
              ),
            ),
          ),
          if (_brands.isNotEmpty || _tabletBrandError != null)
            ReviewCard(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('品牌', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    if (_brands.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 10,
                        children: [
                          for (final brand in _brands)
                            _buildBrandItem(context, brand, primaryGreen),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(child: Text(_tabletBrandError ?? '正在加载品牌')),
                          TextButton(
                            onPressed: _loadTabletBrands,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ReviewCard(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '产品评分',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      _SortChip(
                        label: '热度',
                        selected: _sort == DigitalLibrarySort.hot,
                        onTap: () => _selectSort(DigitalLibrarySort.hot),
                      ),
                      const SizedBox(width: 5),
                      _SortChip(
                        label: '评分',
                        selected: _sort == DigitalLibrarySort.score,
                        onTap: () => _selectSort(DigitalLibrarySort.score),
                      ),
                      const SizedBox(width: 5),
                      _SortChip(
                        label: '最新',
                        selected: _sort == DigitalLibrarySort.newest,
                        onTap: () => _selectSort(DigitalLibrarySort.newest),
                      ),
                    ],
                  ),
                  if (_products.isEmpty)
                    _tabletEmpty(context)
                  else
                    for (var index = 0; index < _products.length; index++)
                      _tabletRankRow(context, index),
                ],
              ),
            ),
          ),
          if (_error != null && _products.isNotEmpty)
            TextButton(
              onPressed: () => _loadProducts(refresh: false),
              child: Text('加载失败，点击重试：$_error'),
            ),
          if (_loading && _products.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _tabletEmpty(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? '暂无产品数据'),
          if (_error != null)
            TextButton(
              onPressed: () => _loadProducts(refresh: true),
              child: const Text('重试'),
            ),
        ],
      ),
    ),
  );

  Widget _tabletHotItem(BuildContext context, int index) {
    final item = _products[index];
    final title = (item['title'] ?? item['name'] ?? '平板').toString();
    final image =
        (item['logo'] ?? item['pic'] ?? item['cover'] ?? item['thumb'] ?? '')
            .toString();
    final hot = (item['hot_num_txt'] ?? item['hot'] ?? item['hot_num'] ?? '')
        .toString();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openTabletProduct(item, title),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (image.isNotEmpty)
                  CachedNetworkImage(
                    normalizeCoolapkImageUrl(image),
                    headers: coolapkImageHeaders(image, api: widget.api),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.tablet_android_rounded, size: 38),
                  )
                else
                  const Icon(Icons.tablet_android_rounded, size: 38),
                Positioned(left: 0, top: 0, child: _tabletRankBadge(index + 1)),
              ],
            ),
          ),
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (hot.isNotEmpty)
            Text(
              '🔥 $hot',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabletRankRow(BuildContext context, int index) {
    final item = _products[index];
    final id = (item['id'] ?? item['productId'] ?? item['entityId'] ?? '')
        .toString();
    final title = (item['title'] ?? item['name'] ?? '平板').toString();
    final image =
        (item['logo'] ?? item['pic'] ?? item['cover'] ?? item['thumb'] ?? '')
            .toString();
    final hot = (item['hot_num_txt'] ?? item['hot'] ?? item['hot_num'] ?? '')
        .toString();
    final comments = (item['feedCommentNumTxt'] ?? item['commentnum'] ?? '')
        .toString();
    final score =
        (item['star_average_score'] ??
                item['score'] ??
                item['recent_30_days_owner_star_average_score'] ??
                '')
            .toString();
    return InkWell(
      onTap: () => _openTabletProduct(item, title, id: id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 66,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (image.isNotEmpty)
                    CachedNetworkImage(
                      normalizeCoolapkImageUrl(image),
                      headers: coolapkImageHeaders(image, api: widget.api),
                      width: 54,
                      height: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.tablet_android_rounded),
                    )
                  else
                    const Icon(Icons.tablet_android_rounded),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: _tabletRankBadge(index + 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (hot.isNotEmpty) '🔥 $hot 热度',
                      if (comments.isNotEmpty) '$comments 讨论',
                    ].join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (score.isNotEmpty)
              Text(
                score,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.tertiary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabletRankBadge(int rank) => DecoratedBox(
    decoration: BoxDecoration(
      color: rank <= 3 ? const Color(0xFFFF9800) : Colors.black38,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        rank.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  void _openTabletProduct(
    Map<String, dynamic> item,
    String title, {
    String? id,
  }) {
    HapticFeedbackUtil.selection();
    final productId =
        id ??
        (item['id'] ?? item['productId'] ?? item['entityId'] ?? '').toString();
    if (productId.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProductPage(api: widget.api, id: productId, title: title),
      ),
    );
  }

  Widget _buildBrandItem(
    BuildContext context,
    Map<String, String> b,
    Color primaryGreen,
  ) {
    final name = b['name'] ?? '';
    final logo = b['logo'] ?? '';
    final isSelected = _selectedBrand == name;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _selectBrand(b),
      child: SizedBox(
        width: 66,
        height: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 36,
              width: 66,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? primaryGreen : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: CachedNetworkImage(
                normalizeCoolapkImageUrl(logo),
                headers: coolapkImageHeaders(logo, api: widget.api),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? primaryGreen : colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colorScheme.onSurface : colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
