import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/recommendation.dart';
import 'package:mangayomi/utils/cached_network.dart';
import 'package:mangayomi/utils/constant.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/platform_utils.dart';

class RecommendationScreen extends StatefulWidget {
  final String name;
  final ItemType itemType;
  final AlgorithmWeights algorithmWeights;

  const RecommendationScreen({
    super.key,
    required this.name,
    required this.itemType,
    required this.algorithmWeights,
  });

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  String _errorMessage = "";
  bool _isLoading = true;
  List<RecommendationResult>? data;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _errorMessage = "";
      data = await getRecommendations(
        widget.name,
        widget.itemType,
        widget.algorithmWeights,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recommendations)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text(_errorMessage))
          : (data == null || data!.isEmpty)
          ? Center(child: Text(l10n.no_result))
          // Poster list: a big cover, the similarity score as a filled pill, the
          // title, a two-line capped synopsis and genre chips. The grid delegate
          // keeps it one column on a phone and reflows to two or more on a wider
          // TV/desktop window (maxCrossAxisExtent), so the rows never stretch
          // into empty space.
          : LayoutBuilder(
              builder: (context, constraints) {
                // One column on a phone, two on anything wider, and never more
                // than two even on a large TV/desktop window.
                final columns = constraints.maxWidth >= 700 ? 2 : 1;
                return GridView.builder(
                  padding: tvPageInsets,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 152,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: data!.length,
                  itemBuilder: (context, index) =>
                      _card(context, data![index], index),
                );
              },
            ),
    );
  }

  Widget _card(BuildContext context, RecommendationResult rec, int index) {
    final title =
        rec.titleEnglish ?? rec.titleRomaji ?? rec.titleNative ?? "";
    final coverUrl = rec.imgURLs.isNotEmpty ? rec.imgURLs.first : "";
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // On TV the first card autofocuses and the focus tint marks the target.
        autofocus: isTv && index == 0,
        focusColor: context.primaryColor.withValues(alpha: 0.16),
        onTap: () => context.push(
          '/globalSearch',
          extra: (title, widget.itemType),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(
                  image: coverProvider(toImgUrl(coverUrl)),
                  width: 94,
                  height: 138,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _scorePill(context, rec.score),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (rec.description != null &&
                        rec.description!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        rec.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: context.textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                    if (rec.genres.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final g in rec.genres.take(3)) _chip(context, g),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Filled with the accent; the label colour is chosen for contrast against the
  // accent (not the theme), so the score stays readable on any accent hue.
  Widget _scorePill(BuildContext context, int score) {
    final accent = context.primaryColor;
    final onAccent = accent.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        "$score%",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: onAccent,
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.textColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: context.textColor.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
