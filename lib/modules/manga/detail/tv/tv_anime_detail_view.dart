import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/library/widgets/library_entry_utils.dart';
import 'package:mangayomi/modules/manga/detail/providers/isar_providers.dart';
import 'package:mangayomi/modules/manga/detail/providers/update_manga_detail_providers.dart';
import 'package:mangayomi/modules/widgets/category_selection_dialog.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/extensions/chapter_extensions.dart';
import 'package:mangayomi/utils/extensions/manga_extensions.dart';

/// TV-only, d-pad-first anime detail. A split view echoing the player settings
/// panel: everything about the title on the left (backdrop, poster, meta, the
/// Play/Continue + Library actions, synopsis) and the episode list on the right.
/// Reached only when `isTv` and the entry is anime.
class TvAnimeDetailView extends ConsumerStatefulWidget {
  const TvAnimeDetailView({super.key, required this.manga});

  final Manga manga;

  @override
  ConsumerState<TvAnimeDetailView> createState() => _TvAnimeDetailViewState();
}

class _TvAnimeDetailViewState extends ConsumerState<TvAnimeDetailView> {
  final _playFocus = FocusNode(debugLabel: 'tvDetailPlay');
  final _libraryFocus = FocusNode(debugLabel: 'tvDetailLibrary');
  final _episodesFocus = FocusNode(debugLabel: 'tvDetailEpisodes');
  final _topBarFocus = FocusNode(debugLabel: 'tvDetailTopBar');
  bool _refreshing = false;

  @override
  void dispose() {
    _playFocus.dispose();
    _libraryFocus.dispose();
    _episodesFocus.dispose();
    _topBarFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(
        updateMangaDetailProvider(mangaId: manga.id, isInit: false).future,
      );
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  Manga get manga => widget.manga;

  /// The episode Play/Continue lands on: the one in watch history, else the
  /// first unwatched, else the first.
  Chapter? _resumeEpisode(List<Chapter> reading) {
    final history = isar.historys
        .filter()
        .mangaIdEqualTo(manga.id!)
        .findAllSync();
    if (history.isNotEmpty) {
      history.first.chapter.loadSync();
      final ch = history.first.chapter.value;
      if (ch != null) return ch;
    }
    for (final c in reading) {
      if (!(c.isRead ?? false)) return c;
    }
    return reading.isNotEmpty ? reading.first : null;
  }

  @override
  Widget build(BuildContext context) {
    // Live episode list; seed the first frame synchronously so it never flashes.
    final chaptersAsync = ref.watch(
      getChaptersStreamProvider(mangaId: manga.id!),
    );
    final hasLive = chaptersAsync.asData != null;
    // getFilteredChapters / getChapterListForReading read the manga.chapters
    // Isar link, which is lazy — load it (refreshed each rebuild the stream
    // triggers) so the episode list isn't empty.
    try {
      manga.chapters.loadSync();
    } catch (_) {}
    // Filtered + sorted (ascending) episodes, respecting the scanlator/chapter
    // filters — the same list the classic detail shows.
    final episodes = manga.getFilteredChapters();
    final reading = manga.getChapterListForReading();
    final resume = _resumeEpisode(reading);
    final watched = episodes.where((c) => c.isRead ?? false).length;

    final cover = resolveCoverImage(manga, ref);
    final bg = Theme.of(context).scaffoldBackgroundColor;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_playFocus.hasFocus &&
          !_episodesFocus.hasFocus &&
          !_libraryFocus.hasFocus &&
          !_topBarFocus.hasFocus) {
        _playFocus.requestFocus();
      }
    });

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred backdrop from the cover.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Image(image: cover, fit: BoxFit.cover),
          ),
          // Darken uniformly enough that text reads over any cover on both
          // columns — so the episode list blends into the same backdrop instead
          // of reading as a separate panel.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  bg,
                  bg.withValues(alpha: 0.92),
                  bg.withValues(alpha: 0.82),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  topBarFocus: _topBarFocus,
                  refreshing: _refreshing,
                  onBack: () => Navigator.maybePop(context),
                  onRefresh: _refresh,
                  onCategories: () => showCategorySelectionDialog(
                    context: context,
                    ref: ref,
                    itemType: manga.itemType,
                    singleManga: manga,
                  ),
                  onMigrate: () => context.push('/migrate', extra: manga),
                  onDown: () => _playFocus.requestFocus(),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 42,
                        child: _LeftInfo(
                          manga: manga,
                          cover: cover,
                          episodeCount: episodes.length,
                          watched: watched,
                          resume: resume,
                          playFocus: _playFocus,
                          libraryFocus: _libraryFocus,
                          onPlay: () => resume?.pushToReaderView(context),
                          onExitRight: () => _episodesFocus.requestFocus(),
                          onExitUp: () => _topBarFocus.requestFocus(),
                          onToggleLibrary: _toggleLibrary,
                        ),
                      ),
                      Expanded(
                        flex: 58,
                        child: _EpisodesPanel(
                          episodes: episodes,
                          resumeId: resume?.id,
                          firstFocus: _episodesFocus,
                          loading: !hasLive && episodes.isEmpty,
                          onExitLeft: () => _playFocus.requestFocus(),
                          onOpen: (c) =>
                              c.pushToReaderView(context, ignoreIsRead: true),
                        ),
                      ),
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

  void _toggleLibrary() {
    final model = manga;
    final now = DateTime.now().millisecondsSinceEpoch;
    isar.writeTxnSync(() {
      model.favorite = !(model.favorite ?? false);
      model.dateAdded = model.favorite! ? now : 0;
      model.updatedAt = now;
      isar.mangas.putSync(model);
    });
    setState(() {});
  }
}

/// Focusable top bar restoring the classic detail's actions (back, refresh,
/// categories, migrate) that a touch-only app bar / pull-to-refresh dropped on
/// TV. Down hands focus to the content below.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.topBarFocus,
    required this.refreshing,
    required this.onBack,
    required this.onRefresh,
    required this.onCategories,
    required this.onMigrate,
    required this.onDown,
  });

  final FocusNode topBarFocus;
  final bool refreshing;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onCategories;
  final VoidCallback onMigrate;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            _TopBarButton(
              focusNode: topBarFocus,
              icon: Icons.arrow_back,
              onPressed: onBack,
            ),
            const Spacer(),
            _TopBarButton(
              icon: refreshing ? Icons.hourglass_empty : Icons.refresh,
              onPressed: onRefresh,
            ),
            _TopBarButton(icon: Icons.label_outline, onPressed: onCategories),
            _TopBarButton(icon: Icons.swap_horiz, onPressed: onMigrate),
          ],
        ),
      ),
    );
  }
}

class _TopBarButton extends StatefulWidget {
  const _TopBarButton({
    required this.icon,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<_TopBarButton> createState() => _TopBarButtonState();
}

class _TopBarButtonState extends State<_TopBarButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _isSelect(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _focused ? accent : accent.withValues(alpha: 0.12),
          ),
          child: Icon(
            widget.icon,
            size: 22,
            color: _focused ? Colors.white : accent,
          ),
        ),
      ),
    );
  }
}

class _LeftInfo extends StatelessWidget {
  const _LeftInfo({
    required this.manga,
    required this.cover,
    required this.episodeCount,
    required this.watched,
    required this.resume,
    required this.playFocus,
    required this.libraryFocus,
    required this.onPlay,
    required this.onExitRight,
    required this.onExitUp,
    required this.onToggleLibrary,
  });

  final Manga manga;
  final ImageProvider cover;
  final int episodeCount;
  final int watched;
  final Chapter? resume;
  final FocusNode playFocus;
  final FocusNode libraryFocus;
  final VoidCallback onPlay;
  final VoidCallback onExitRight;
  final VoidCallback onExitUp;
  final VoidCallback onToggleLibrary;

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    final genres = (manga.genre ?? const <String>[]).take(4).join('  ·  ');
    final metaBits = <String>[
      manga.status.name.isNotEmpty ? _cap(manga.status.name) : '',
      '$episodeCount episodes',
      if ((manga.source ?? '').isNotEmpty) manga.source!,
      if ((manga.author ?? '').isNotEmpty) manga.author!,
    ].where((s) => s.isNotEmpty).join('   ·   ');
    final favorite = manga.favorite ?? false;
    final resumeLabel = resume == null
        ? 'Play'
        : (resume!.isRead ?? false)
        ? 'Replay ${resume!.name ?? ''}'.trim()
        : (watched > 0 ? 'Continue' : 'Play');

    // Right anywhere in this column hands focus to the episode list.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            onExitRight();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            onExitUp();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 150,
                    child: AspectRatio(
                      aspectRatio: 0.68,
                      child: Image(image: cover, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manga.name ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (metaBits.isNotEmpty)
                        Text(
                          metaBits,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      if (genres.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          genres,
                          style: TextStyle(fontSize: 12, color: accent),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _ActionButton(
                  focusNode: playFocus,
                  autofocus: true,
                  accent: accent,
                  filled: true,
                  icon: Icons.play_arrow_rounded,
                  label: resumeLabel,
                  onPressed: onPlay,
                ),
                const SizedBox(width: 12),
                _ActionButton(
                  focusNode: libraryFocus,
                  accent: accent,
                  filled: false,
                  icon: favorite ? Icons.favorite : Icons.favorite_border,
                  label: favorite ? 'In Library' : 'Add to Library',
                  onPressed: onToggleLibrary,
                ),
              ],
            ),
            if ((manga.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                manga.description!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyLarge!.color!.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.accent,
    required this.filled,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final Color accent;
  final bool filled;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.filled;
    final bg = active
        ? widget.accent
        : widget.accent.withValues(alpha: 0.16);
    final fg = active ? Colors.white : widget.accent;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _isSelect(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.identity()..scale(_focused ? 1.05 : 1.0),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: fg, size: 22),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodesPanel extends StatelessWidget {
  const _EpisodesPanel({
    required this.episodes,
    required this.resumeId,
    required this.firstFocus,
    required this.loading,
    required this.onExitLeft,
    required this.onOpen,
  });

  final List<Chapter> episodes;
  final int? resumeId;
  final FocusNode firstFocus;
  final bool loading;
  final VoidCallback onExitLeft;
  final ValueChanged<Chapter> onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    // No panel surface — the list sits over the same backdrop as the left side
    // (Netflix-style), with only a faint edge line hinting the column.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).hintColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              'Episodes  ·  ${episodes.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).hintColor.withValues(alpha: 0.2),
          ),
          Expanded(
            child: loading
                ? const SizedBox.shrink()
                : episodes.isEmpty
                ? Center(
                    child: Text(
                      'No episodes yet',
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  )
                : FocusTraversalGroup(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: episodes.length,
                      itemBuilder: (context, i) {
                        final ep = episodes[i];
                        return _EpisodeRow(
                          accent: accent,
                          episode: ep,
                          index: i,
                          isResume: ep.id != null && ep.id == resumeId,
                          focusNode: i == 0 ? firstFocus : null,
                          onOpen: () => onOpen(ep),
                          onExitLeft: onExitLeft,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.accent,
    required this.episode,
    required this.index,
    required this.isResume,
    required this.focusNode,
    required this.onOpen,
    required this.onExitLeft,
  });

  final Color accent;
  final Chapter episode;
  final int index;
  final bool isResume;
  final FocusNode? focusNode;
  final VoidCallback onOpen;
  final VoidCallback onExitLeft;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final watched = ep.isRead ?? false;
    final filler = ep.isFiller ?? false;
    final title = (ep.name ?? '').trim().isEmpty
        ? 'Episode ${widget.index + 1}'
        : ep.name!.trim();
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onExitLeft();
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent && _isSelect(event.logicalKey)) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accent.withValues(alpha: 0.20)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: widget.isResume
                    ? Icon(Icons.play_arrow_rounded, color: widget.accent)
                    : Text(
                        '${widget.index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: watched
                              ? Theme.of(context).hintColor
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: watched ? Theme.of(context).hintColor : null,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (filler)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Theme.of(context).hintColor),
                  ),
                  child: Text(
                    'FILLER',
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              if ((ep.duration ?? '').isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  ep.duration!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
              if (watched)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Theme.of(context).hintColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSelect(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA ||
    k == LogicalKeyboardKey.space;
