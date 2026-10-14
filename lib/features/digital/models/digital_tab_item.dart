class DigitalTabItem {
  final String key;
  final String title;
  final String url;
  final String? pageName;
  final String? subTitle;
  final bool category;
  final String? categoryId;

  const DigitalTabItem({
    required this.key,
    required this.title,
    required this.url,
    this.pageName,
    this.subTitle,
    this.category = false,
    this.categoryId,
  });

  static List<DigitalTabItem> getFallbackTabs() => const [
    DigitalTabItem(
      key: 'V10_PRODUCT_LIBRARY',
      title: '数码库',
      url: '/v6/product/categoryList',
      category: true,
    ),
    DigitalTabItem(
      key: 'V10_DIGITAL_HOME',
      title: '数码',
      url: 'V10_DIGITAL_HOME',
      pageName: 'V10_DIGITAL_HOME',
    ),
    DigitalTabItem(
      key: 'V10_CHANNEL_SJB',
      title: '手机',
      url: 'V10_CHANNEL_SJB',
      pageName: 'V10_CHANNEL_SJB',
    ),
    DigitalTabItem(
      key: 'V10_CHANNEL_SMB_TOP',
      title: '排行榜',
      url: 'V10_CHANNEL_SMB_TOP',
      pageName: 'V10_CHANNEL_SMB_TOP',
    ),
    DigitalTabItem(
      key: 'V10_CHANNEL_SMB',
      title: '系统',
      url: 'V10_CHANNEL_SMB',
      pageName: 'V10_CHANNEL_SMB',
    ),
    DigitalTabItem(
      key: 'V15_PAD',
      title: '平板',
      url: 'V15_PAD',
      pageName: 'V15_PAD',
    ),
    DigitalTabItem(
      key: 'V8_ZHUANTI_COMPUTER_20230413',
      title: '电脑',
      url: 'V8_ZHUANTI_COMPUTER_20230413',
      pageName: 'V8_ZHUANTI_COMPUTER_20230413',
    ),
  ];
}
