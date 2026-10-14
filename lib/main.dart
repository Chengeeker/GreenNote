import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/coolapk_api.dart';
import 'core/network/http_overrides.dart';
import 'core/settings/app_settings.dart';
import 'core/design_system/components/review_navigation_bar.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_toast.dart';
import 'core/utils/haptic_feedback_util.dart';
import 'core/design_system/components/review_frosted_app_bar.dart';
import 'core/widgets/app_avatar.dart';
import 'features/feed/feed_pages.dart';
import 'features/settings/app_settings_page.dart';
import 'features/shared/api_list_page.dart';
import 'features/shell/main_pages.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = AppHttpOverrides();
  PaintingBinding.instance.imageCache.maximumSize = 3000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 * 1024 * 1024; // 512MB
  runApp(const ProviderScope(child: GreennoteApp()));
}

class GreennoteApp extends ConsumerWidget {
  const GreennoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    HapticFeedbackUtil.isEnabled = settings.enableHaptics;
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final seed = Color(settings.themeSeedArgb);
        final light = settings.useDynamicColor && lightDynamic != null
            ? lightDynamic
            : ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.light,
              );
        final dark = settings.useDynamicColor && darkDynamic != null
            ? darkDynamic
            : ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              );
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'GreenNote',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.lightTheme(
            dynamicColorScheme: light,
            fontWeightAdjustment: settings.effectiveFontWeightAdjustment,
          ),
          darkTheme: AppTheme.darkTheme(
            dynamicColorScheme: dark,
            isPureBlack: settings.isPureBlackDark,
            fontWeightAdjustment: settings.effectiveFontWeightAdjustment,
          ),
          themeMode: settings.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(settings.fontScale)),
            child: DefaultTextStyle(
              style:
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: const MainScaffold(),
        );
      },
    );
  }
}

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  int _accountRevision = 0;
  bool _isTabTransitioning = false;
  final Set<int> _visitedTabs = {0};
  final Set<int> _pageTabBarsReady = {};
  final List<PreferredSizeWidget?> _pageTabBars = List.filled(4, null);
  late final AnimationController _tabTransitionController;
  late final CurvedAnimation _tabTransitionCurve;
  late Animation<Offset> _tabIncomingTransition;
  late Animation<Offset> _tabOutgoingTransition;
  CoolapkApi? _initializedApi;

  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _tabTransitionCurve = CurvedAnimation(
      parent: _tabTransitionController,
      curve: Curves.easeOutCubic,
    );
    _tabIncomingTransition = const AlwaysStoppedAnimation(Offset.zero);
    _tabOutgoingTransition = const AlwaysStoppedAnimation(Offset.zero);
    _tabTransitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _isTabTransitioning &&
          mounted) {
        setState(() => _isTabTransitioning = false);
      }
    });
  }

  @override
  void dispose() {
    _tabTransitionCurve.dispose();
    _tabTransitionController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    HapticFeedbackUtil.selection();
    if (MediaQuery.disableAnimationsOf(context)) {
      _tabTransitionController.stop();
      setState(() {
        _visitedTabs.add(index);
        _previousIndex = index;
        _selectedIndex = index;
        _isTabTransitioning = false;
        _tabIncomingTransition = const AlwaysStoppedAnimation(Offset.zero);
        _tabOutgoingTransition = const AlwaysStoppedAnimation(Offset.zero);
      });
      _tabTransitionController.value = 1;
      return;
    }

    final currentOffset = _isTabTransitioning
        ? _tabIncomingTransition.value
        : Offset.zero;
    var direction = index > _selectedIndex ? 1.0 : -1.0;
    if (Directionality.of(context) == TextDirection.rtl) direction *= -1;
    setState(() {
      _visitedTabs.add(index);
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
      _isTabTransitioning = true;
      _tabIncomingTransition = Tween<Offset>(
        begin: Offset(direction, 0),
        end: Offset.zero,
      ).animate(_tabTransitionCurve);
      _tabOutgoingTransition = Tween<Offset>(
        begin: currentOffset,
        end: Offset(-direction, 0),
      ).animate(_tabTransitionCurve);
    });
    _tabTransitionController.forward(from: 0);
  }

  void _setPageTabBar(int index, PreferredSizeWidget? tabBar) {
    if (!mounted) return;
    final changed =
        !_pageTabBarsReady.contains(index) ||
        !identical(_pageTabBars[index], tabBar);
    _pageTabBarsReady.add(index);
    if (!changed) return;
    setState(() => _pageTabBars[index] = tabBar);
  }

  PreferredSizeWidget? _currentPageTabBar() {
    if (_selectedIndex == 3 || _pageTabBarsReady.contains(_selectedIndex)) {
      return _pageTabBars[_selectedIndex];
    }
    return const PreferredSize(
      preferredSize: Size.fromHeight(kTextTabBarHeight),
      child: SizedBox(height: kTextTabBarHeight),
    );
  }

  void _accountChanged() {
    if (mounted) setState(() => _accountRevision++);
  }

  int _tabPageLayer(int index) {
    if (_isTabTransitioning && index == _previousIndex) return 1;
    if (index == _selectedIndex) return 2;
    return 0;
  }

  Widget _buildTabContent(BuildContext context, CoolapkApi api) {
    final pages = <Widget>[
      FeedHomePage(
        api: api,
        onTopBarChanged: (tabBar) => _setPageTabBar(0, tabBar),
        onLoginRequested: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => CookieLoginPage(api: api)),
          );
        },
      ),
      DigitalPage(
        api: api,
        onTopBarChanged: (tabBar) => _setPageTabBar(1, tabBar),
      ),
      DiscoveryPage(
        api: api,
        onTopBarChanged: (tabBar) => _setPageTabBar(2, tabBar),
      ),
      AccountPage(api: api, accountRevision: _accountRevision),
    ];
    final pageOrder = _visitedTabs.toList()
      ..sort((a, b) => _tabPageLayer(a).compareTo(_tabPageLayer(b)));
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final index in pageOrder)
          Positioned.fill(
            key: ValueKey(index),
            child: Offstage(
              offstage:
                  index != _selectedIndex &&
                  (!_isTabTransitioning || index != _previousIndex),
              child: TickerMode(
                enabled:
                    index == _selectedIndex ||
                    (_isTabTransitioning && index == _previousIndex),
                child: IgnorePointer(
                  ignoring: index != _selectedIndex,
                  child: SlideTransition(
                    position: index == _selectedIndex
                        ? _tabIncomingTransition
                        : index == _previousIndex && _isTabTransitioning
                        ? _tabOutgoingTransition
                        : const AlwaysStoppedAnimation(Offset.zero),
                    child: pages[index],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAppBadgeButton(BuildContext context, CoolapkApi client) {
    return IconButton(
      tooltip: '应用精选',
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ApiListPage(api: client, title: '应用精选', path: '/v6/apk/rankList'),
        ),
      ),
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'APP',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageButton(BuildContext context, CoolapkApi client) {
    return IconButton(
      tooltip: '消息',
      icon: const Icon(Icons.mail_outline_rounded),
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: ReviewFrostedAppBar(title: const Text('消息')),
            body: MessageCenterPage(api: client),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchCapsule(
    BuildContext context,
    CoolapkApi client,
    String hint,
  ) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => SearchHubPage(api: client)),
      ),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.search_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, CoolapkApi client) {
    if (_selectedIndex == 3) {
      return ReviewFrostedAppBar(
        titleSpacing: 4,
        title: const SizedBox.shrink(),
        bottom: _currentPageTabBar(),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SearchHubPage(api: client),
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AppSettingsPage(
                  api: client,
                  onOpenCookieManager: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CookieLoginPage(api: client),
                      ),
                    );
                  },
                  onAccountChanged: _accountChanged,
                ),
              ),
            ),
          ),
          _buildAppBadgeButton(context, client),
          _buildMessageButton(context, client),
          const SizedBox(width: 4),
        ],
      );
    }

    final String hint;
    switch (_selectedIndex) {
      case 0:
        hint = '搜索动态/话题/应用/酷友...';
        break;
      case 1:
        hint = '搜索动态/机型...';
        break;
      case 2:
      default:
        hint = '搜索应用、游戏、好物与精选...';
        break;
    }

    return ReviewFrostedAppBar(
      titleSpacing: 10,
      bottom: _currentPageTabBar(),
      leadingWidth: 54,
      leading: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Center(
          child: GestureDetector(
            onTap: () => _selectTab(3),
            child: AppAvatar(
              url: client.currentUserAvatar.isNotEmpty
                  ? client.currentUserAvatar
                  : null,
              api: client,
              size: 34,
            ),
          ),
        ),
      ),
      title: _buildSearchCapsule(context, client, hint),
      actions: [
        _buildAppBadgeButton(context, client),
        _buildMessageButton(context, client),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(coolapkApiProvider);
    final floating = ref.watch(
      appSettingsProvider.select((s) => s.useFloatingNavBar),
    );
    return api.when(
      loading: () => const _StartupScaffold(),
      error: (error, _) => _StartupScaffold(
        error: error.toString(),
        onRetry: () => ref.invalidate(coolapkApiProvider),
      ),
      data: (client) {
        if (!identical(_initializedApi, client)) {
          _initializedApi = client;
          unawaited(
            client.loadHomeTabRoutes().then<void>((_) {}).catchError((_) {}),
          );
        }
        return Scaffold(
          extendBody: floating,
          appBar: _buildAppBar(context, client),
          body: _buildTabContent(context, client),
          bottomNavigationBar: ReviewNavigationBar(
            selectedIndex: _selectedIndex >= 2
                ? _selectedIndex + 1
                : _selectedIndex,
            hasBottomInset: MediaQuery.paddingOf(context).bottom > 0,
            onSelected: (index) {
              if (index == 2) {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ComposeFeedPage(api: client),
                  ),
                );
              } else {
                _selectTab(index > 2 ? index - 1 : index);
              }
            },
          ),
        );
      },
    );
  }
}

class _StartupScaffold extends StatelessWidget {
  const _StartupScaffold({this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ReviewFrostedAppBar(title: const Text('GreenNote')),
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: onRetry,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
