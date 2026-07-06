import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/category.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/library/providers/isar_providers.dart';
import 'package:mangayomi/modules/library/widgets/library_entry_utils.dart';
import 'package:mangayomi/modules/more/categories/providers/isar_providers.dart';
import 'package:mangayomi/modules/widgets/bottom_text_widget.dart';
import 'package:mangayomi/modules/widgets/cover_view_widget.dart';
import 'package:mangayomi/modules/widgets/error_text.dart';
import 'package:mangayomi/modules/widgets/progress_center.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/extensions/chapter_extensions.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// TV-only, d-pad-first anime home. Instead of the flat grid it shows a hero
/// (the thing you'll resume) plus horizontal rows — Continue Watching, New
/// Episodes, Recently Added, then one row per category. Rows are inherently
/// d-pad-native (Up/Down between rows, Left/Right within), which removes the
/// grid's 2D-traversal surprises. Rendered only when `isTv` + `tvHomeStyle`.
///
/// The d-pad contract: focus lands on the hero's Continue on first frame;
/// Left at a row's first card falls through to the nav rail (handled by
/// `_handleTvKey` in main_screen, since this lives in the content FocusScope);
/// focus drives scroll — each card scrolls itself into view when focused.
class TvAnimeHomeView extends ConsumerWidget {
  const TvAnimeHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animeAsync = ref.watch(
      getAllMangaStreamProvider(categoryId: null, itemType: ItemType.anime),
    );
    final catsAsync = ref.watch(
      getMangaCategorieStreamProvider(itemType: ItemType.anime),
    );

    return Scaffold(
      body: animeAsync.when(
        loading: () => const ProgressCenter(),
        error: (e, _) => ErrorText(e),
        data: (allAnime) {
          if (allAnime.isEmpty) return const _EmptyHome();

          // All rows derive from the single loaded anime list — no extra reads.
          final continueList =
              allAnime.where((m) => (m.lastRead ?? 0) > 0).toList()
                ..sort((a, b) => (b.lastRead ?? 0).compareTo(a.lastRead ?? 0));
          final newEpisodes =
              allAnime
                  .where((m) => m.chapters.any((c) => !(c.isRead ?? true)))
                  .toList()
                ..sort(
                  (a, b) => (b.lastUpdate ?? 0).compareTo(a.lastUpdate ?? 0),
                );
          final recent = [...allAnime]
            ..sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));

          final hero = continueList.isNotEmpty
              ? continueList.first
              : recent.first;

          final cats =
              (catsAsync.asData?.value ?? const <Category>[])
                  .where((c) => !(c.hide ?? false))
                  .toList()
                ..sort((a, b) => (a.pos ?? 0).compareTo(b.pos ?? 0));

          return ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              _TvHomeHero(manga: hero),
              if (continueList.isNotEmpty)
                _TvHomeRow(title: 'Continue Watching', items: continueList),
              if (newEpisodes.isNotEmpty)
                _TvHomeRow(title: 'New Episodes', items: newEpisodes),
              _TvHomeRow(title: 'Recently Added', items: recent),
              for (final cat in cats) _TvCategoryRow(category: cat),
            ],
          );
        },
      ),
    );
  }
}

/// The top hero: an ambient blurred backdrop derived from the cover, the poster,
/// title + a quick summary, and the (autofocused) Continue button.
class _TvHomeHero extends ConsumerWidget {
  const _TvHomeHero({required this.manga});
  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = resolveCoverImage(manga, ref);
    final unread = manga.chapters.where((c) => !(c.isRead ?? true)).length;
    final bits = <String>[
      if (unread > 0) '$unread new',
      if ((manga.source ?? '').isNotEmpty) manga.source!,
    ];

    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient blurred backdrop from the cover itself.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Image(image: image, fit: BoxFit.cover),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.black.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 0.68,
                    child: Image(image: image, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        manga.name ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (bits.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          bits.join('  ·  '),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _HeroContinueButton(manga: manga),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero's Continue button — focusable, autofocused (the home's landing
/// target), theme-accent when focused, OK/Select or tap to resume.
class _HeroContinueButton extends StatefulWidget {
  const _HeroContinueButton({required this.manga});
  final Manga manga;

  @override
  State<_HeroContinueButton> createState() => _HeroContinueButtonState();
}

class _HeroContinueButtonState extends State<_HeroContinueButton> {
  bool _focused = false;

  void _resume() {
    // Mirror ContinueReaderButton: resume the last-watched episode from history,
    // else start from the first chapter.
    final history = isar.historys
        .filter()
        .mangaIdEqualTo(widget.manga.id!)
        .findAllSync();
    if (history.isNotEmpty) {
      // findAllSync doesn't hydrate the linked chapter — load it explicitly so
      // Continue resumes the last-watched episode instead of restarting at #1.
      final last = history.first;
      last.chapter.loadSync();
      if (last.chapter.value != null) {
        last.chapter.value!.pushToReaderView(context);
        return;
      }
    }
    if (widget.manga.chapters.isNotEmpty) {
      widget.manga.chapters.first.pushToReaderView(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    return Focus(
      autofocus: true,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _isSelectKey(event.logicalKey)) {
          _resume();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _resume,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _focused ? accent : Colors.white.withValues(alpha: 0.14),
            border: Border.all(
              color: _focused ? accent : Colors.white.withValues(alpha: 0.28),
              width: 2,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled horizontal row of cover cards.
class _TvHomeRow extends StatelessWidget {
  const _TvHomeRow({required this.title, required this.items});
  final String title;
  final List<Manga> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          SizedBox(
            height: 214,
            // Each row is its own traversal group so directional focus stays
            // predictable across rows.
            child: FocusTraversalGroup(
              child: SuperListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _TvHomeCard(manga: items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single category's row — watches its own membership stream and hides itself
/// when empty.
class _TvCategoryRow extends ConsumerWidget {
  const _TvCategoryRow({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref
            .watch(
              getAllMangaStreamProvider(
                categoryId: category.id,
                itemType: ItemType.anime,
              ),
            )
            .asData
            ?.value ??
        const <Manga>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return _TvHomeRow(title: category.name ?? '', items: items);
  }
}

/// A cover card in a row: reuses [CoverViewWidget] (focus ring + badges) and
/// scrolls itself into view when focused (focus drives scroll). Select → detail.
class _TvHomeCard extends ConsumerWidget {
  const _TvHomeCard({required this.manga});
  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = manga.chapters.where((c) => !(c.isRead ?? true)).length;
    final source = manga.source ?? '';
    return SizedBox(
      width: 128,
      child: CoverViewWidget(
        isComfortableGrid: true,
        bottomTextWidget: BottomTextWidget(
          text: manga.name ?? '',
          maxLines: 1,
          isComfortableGrid: true,
        ),
        image: resolveCoverImage(manga, ref),
        onFocusChange: (focused) {
          if (focused && context.mounted) {
            // Reveal the focused card in both the row (horizontal) and the
            // page (vertical) — one call walks up every enclosing scrollable.
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        },
        onTap: () => onTapEntry(
          isLongPressed: false,
          ref: ref,
          context: context,
          entry: manga,
        ),
        children: [
          if (unread > 0)
            Positioned(
              top: 0,
              left: 0,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: context.primaryColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$unread',
                    style: TextStyle(
                      color: context.dynamicBlackWhiteColor,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          if (source.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 92),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(3),
                    ),
                  ),
                  child: Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when the anime library is empty. Crucially it carries a *focusable*
/// action: without one, the empty content has no focus target, so pressing
/// Right from the rail lands on nothing and there's nothing to move Left from
/// to get back — a d-pad dead end. The autofocused Browse button is that target
/// (and Left from it falls through to the rail via the existing handler).
class _EmptyHome extends StatefulWidget {
  const _EmptyHome();

  @override
  State<_EmptyHome> createState() => _EmptyHomeState();
}

class _EmptyHomeState extends State<_EmptyHome> {
  bool _focused = false;

  void _browse() => context.go('/browse');

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    final hint = Theme.of(context).hintColor;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, size: 56, color: hint),
          const SizedBox(height: 16),
          const Text(
            'Your anime library is empty',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Add anime from Browse to fill your home',
            style: TextStyle(color: hint),
          ),
          const SizedBox(height: 22),
          Focus(
            autofocus: true,
            onFocusChange: (f) => setState(() => _focused = f),
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && _isSelectKey(event.logicalKey)) {
                _browse();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: _browse,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _focused ? accent : Colors.transparent,
                  border: Border.all(color: accent, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      color: _focused ? Colors.white : accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Browse anime',
                      style: TextStyle(
                        color: _focused ? Colors.white : accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA ||
    k == LogicalKeyboardKey.space;
