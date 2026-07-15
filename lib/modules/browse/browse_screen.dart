import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/source.dart';
import 'package:mangayomi/modules/more/settings/reader/providers/reader_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/modules/browse/extension/extension_screen.dart';
import 'package:mangayomi/modules/browse/sources/sources_screen.dart';
import 'package:mangayomi/modules/main_view/providers/tv_mode_provider.dart';
import 'package:mangayomi/modules/library/widgets/search_text_form_field.dart';
import 'package:mangayomi/modules/widgets/tv_pill.dart';
import 'package:mangayomi/services/fetch_sources_list.dart';
import 'package:mangayomi/utils/item_type_localization.dart';
import 'package:mangayomi/utils/platform_utils.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

enum BrowseTabKind { sources, extensions }

class BrowseTab {
  final ItemType type;
  final BrowseTabKind kind;

  const BrowseTab(this.type, this.kind);
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with TickerProviderStateMixin {
  late final hideItems = ref.read(hideItemsStateProvider);
  final _textEditingController = TextEditingController();
  late TabController _tabBarController;
  late List<BrowseTab> _tabList;

  // TV top-bar focus ladder: [icons, pills, list]. Up/Down hops between these
  // scopes at the edges so the top bar never steals focus. See #729.
  final FocusScopeNode _iconsScope = FocusScopeNode(debugLabel: 'browseIcons');
  final FocusScopeNode _pillsScope = FocusScopeNode(debugLabel: 'browsePills');
  final FocusScopeNode _bodyScope = FocusScopeNode(debugLabel: 'browseBody');
  List<FocusScopeNode> get _order => [_iconsScope, _pillsScope, _bodyScope];

  // Hide manga & novel from Browse (sources + extensions) on the anime-only TV
  // layout so only anime shows. Recomputed live so toggling "Anime only" updates
  // the tabs without a restart. Defaults to isTv, user-overridable. See #729.
  List<BrowseTab> _computeTabList(bool animeOnly) => [
    if (!animeOnly && !hideItems.contains("/MangaLibrary"))
      BrowseTab(ItemType.manga, BrowseTabKind.sources),
    if (!hideItems.contains("/AnimeLibrary"))
      BrowseTab(ItemType.anime, BrowseTabKind.sources),
    if (!animeOnly && !hideItems.contains("/NovelLibrary"))
      BrowseTab(ItemType.novel, BrowseTabKind.sources),
    if (!animeOnly && !hideItems.contains("/MangaLibrary"))
      BrowseTab(ItemType.manga, BrowseTabKind.extensions),
    if (!hideItems.contains("/AnimeLibrary"))
      BrowseTab(ItemType.anime, BrowseTabKind.extensions),
    if (!animeOnly && !hideItems.contains("/NovelLibrary"))
      BrowseTab(ItemType.novel, BrowseTabKind.extensions),
  ];

  @override
  void initState() {
    super.initState();
    _tabList = _computeTabList(ref.read(animeOnlyTvModeProvider));
    _tabBarController = TabController(length: _tabList.length, vsync: this);
    _tabBarController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    _chekPermission();
    setState(() {
      _textEditingController.clear();
      _isSearch = false;
    });
  }

  Future<void> _chekPermission() async {
    await StorageProvider().requestPermission();
  }

  @override
  void dispose() {
    _tabBarController.dispose();
    _textEditingController.dispose();
    _iconsScope.dispose();
    _pillsScope.dispose();
    _bodyScope.dispose();
    super.dispose();
  }

  // Move focus between the ordered top-bar sections on Up/Down. Within the list
  // (bodyScope) let its own rows move first; only hop to the adjacent section at
  // the top/bottom edge. Left/Right are ignored here (row buttons + nav rail).
  KeyEventResult _handleVertical(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if (k != LogicalKeyboardKey.arrowDown && k != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final cur = _order.indexWhere((s) => s.hasFocus);
    if (cur == -1) return KeyEventResult.ignored;
    final down = k == LogicalKeyboardKey.arrowDown;
    if (identical(_order[cur], _bodyScope)) {
      final moved =
          FocusManager.instance.primaryFocus?.focusInDirection(
            down ? TraversalDirection.down : TraversalDirection.up,
          ) ??
          false;
      if (moved) return KeyEventResult.handled;
    }
    final target = down ? cur + 1 : cur - 1;
    if (target < 0 || target >= _order.length) return KeyEventResult.ignored;
    final curDesc = _order[cur].traversalDescendants.toList();
    final col = curDesc.indexWhere((n) => n.hasPrimaryFocus);
    _focusSection(_order[target], col < 0 ? 0 : col);
    return KeyEventResult.handled;
  }

  bool _focusSection(FocusScopeNode scope, int column) {
    final descendants = scope.traversalDescendants.toList();
    if (descendants.isEmpty) return false;
    descendants[column.clamp(0, descendants.length - 1)].requestFocus();
    return true;
  }

  bool _isSearch = false;

  /// The top-bar action icons, which differ per tab (see #729): Sources =
  /// global-search + filter; Extensions = add + search + language filter.
  List<Widget> _actions(
    BuildContext context,
    bool isExtensionTab,
    ItemType tabType,
  ) {
    return [
      _isSearch
          ? SeachFormTextField(
              onChanged: (value) {
                setState(() {});
              },
              onSuffixPressed: () {
                _textEditingController.clear();
              },
              onPressed: () {
                setState(() {
                  _isSearch = false;
                });
                _textEditingController.clear();
              },
              controller: _textEditingController,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isExtensionTab)
                  IconButton(
                    onPressed: () {
                      context.push('/createExtension');
                    },
                    icon: Icon(
                      Icons.add_outlined,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                IconButton(
                  splashRadius: 20,
                  onPressed: () {
                    if (isExtensionTab) {
                      setState(() {
                        _isSearch = true;
                      });
                    } else {
                      context.push('/globalSearch', extra: (null, tabType));
                    }
                  },
                  icon: Icon(
                    !isExtensionTab
                        ? Icons.travel_explore_rounded
                        : Icons.search_rounded,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
      IconButton(
        splashRadius: 20,
        onPressed: () {
          context.push(
            isExtensionTab ? '/ExtensionLang' : '/sourceFilter',
            extra: tabType,
          );
        },
        icon: Icon(
          !isExtensionTab ? Icons.filter_list_sharp : Icons.translate_rounded,
          color: Theme.of(context).hintColor,
        ),
      ),
    ];
  }

  List<Widget> _tabViews() => _tabList.map((tab) {
    if (tab.kind == BrowseTabKind.sources) {
      return SourcesScreen(
        itemType: tab.type,
        tabs: _tabList,
        tabIndex: (index) => _tabBarController.animateTo(index),
      );
    }
    return ExtensionScreen(
      query: _textEditingController.text,
      itemType: tab.type,
    );
  }).toList();

  // Android TV Browse: pill tabs (matching the home) + a top-bar focus ladder
  // (icons -> pills -> list) so nothing steals focus on Up. See #729.
  Widget _buildTvLayout(
    BuildContext context,
    BrowseTab currentTab,
    bool isExtensionTab,
    AppLocalizations l10n,
  ) {
    return DefaultTabController(
      animationDuration: Duration.zero,
      length: _tabList.length,
      child: Scaffold(
        body: SafeArea(
          child: Focus(
            onKeyEvent: _handleVertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FocusScope(
                  node: _iconsScope,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                    child: Row(
                      children: [
                        Text(
                          l10n.browse,
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        ..._actions(context, isExtensionTab, currentTab.type),
                      ],
                    ),
                  ),
                ),
                FocusScope(
                  node: _pillsScope,
                  child: SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      children: [
                        for (int i = 0; i < _tabList.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Center(
                              child: TvPill(
                                label:
                                    _tabList[i].kind == BrowseTabKind.extensions
                                    ? _tabList[i].type.localizedExtensions(l10n)
                                    : _tabList[i].type.localizedSources(l10n),
                                selected: i == _tabBarController.index,
                                onTap: () {
                                  _tabBarController.animateTo(i);
                                  setState(() {});
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: FocusScope(
                    node: _bodyScope,
                    child: TabBarView(
                      controller: _tabBarController,
                      children: _tabViews(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Recompute the tab list live when "Anime only" flips; recreate the
    // controller when the tab count changes.
    final newTabs = _computeTabList(ref.watch(animeOnlyTvModeProvider));
    if (newTabs.length != _tabList.length) {
      _tabList = newTabs;
      _tabBarController.removeListener(_onTabChanged);
      _tabBarController.dispose();
      _tabBarController = TabController(length: _tabList.length, vsync: this);
      _tabBarController.addListener(_onTabChanged);
    } else {
      _tabList = newTabs;
    }
    if (_tabList.isEmpty) {
      return SizedBox.shrink();
    }
    final currentTab = _tabList[_tabBarController.index];
    final isExtensionTab = currentTab.kind == BrowseTabKind.extensions;

    final l10n = l10nLocalizations(context)!;
    if (isTv) {
      return _buildTvLayout(context, currentTab, isExtensionTab, l10n);
    }
    return DefaultTabController(
      animationDuration: Duration.zero,
      length: _tabList.length,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: Text(
            l10n.browse,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          actions: _actions(context, isExtensionTab, currentTab.type),
          bottom: TabBar(
            indicatorSize: TabBarIndicatorSize.label,
            isScrollable: true,
            controller: _tabBarController,
            tabs: _tabList.map((tab) {
              final type = tab.type;
              final isExt = tab.kind == BrowseTabKind.extensions;

              return Tab(
                child: Row(
                  children: [
                    Text(
                      isExt
                          ? type.localizedExtensions(l10n)
                          : type.localizedSources(l10n),
                    ),
                    if (isExt) ...[
                      const SizedBox(width: 8),
                      _extensionUpdateNumbers(ref, type),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        body: TabBarView(
          controller: _tabBarController,
          children: _tabViews(),
        ),
      ),
    );
  }
}

Widget _extensionUpdateNumbers(WidgetRef ref, ItemType itemType) {
  return StreamBuilder(
    stream: isar.sources
        .filter()
        .idIsNotNull()
        .and()
        .isActiveEqualTo(true)
        .itemTypeEqualTo(itemType)
        .watch(fireImmediately: true),
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data!.isNotEmpty) {
        final entries = snapshot.data!
            .where(
              (element) =>
                  compareVersions(element.version!, element.versionLast!) < 0,
            )
            .toList();
        return entries.isEmpty
            ? SizedBox.shrink()
            : Badge(
                backgroundColor: Theme.of(context).focusColor,
                label: Text(
                  entries.length.toString(),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall!.color,
                  ),
                ),
              );
      }
      return Container();
    },
  );
}
