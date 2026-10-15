import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';

void main() {
  test('discovery routes parse current and legacy init section titles', () {
    const routes = {
      '生活': '/page?url=V15_ZHUANTI_SHENGHUO',
      '二手': '/page?url=V11_DISCOVERY_SECOND_HAND',
      '宠物': '/page?url=V15_CHONGWU',
      '运动': '/page?url=V15_YUNDONG',
      '商家': '/page?url=V14_SALE',
    };

    for (final title in ['发现', '发现TAB配置']) {
      final parsed = CoolapkApi.parseDiscoveryTabRoutes({
        'data': [
          {
            'title': title,
            'entities': [
              for (final route in routes.entries)
                {'title': route.key, 'url': route.value},
            ],
          },
        ],
      });

      expect(parsed, routes);
    }
  });
}
