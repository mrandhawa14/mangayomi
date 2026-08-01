import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/widgets/bottom_text_widget.dart';
import 'package:mangayomi/modules/widgets/cover_view_widget.dart';
import 'package:mangayomi/modules/widgets/gridview_widget.dart';
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
          // Cover-forward grid: the poster is the tile, the title sits beneath
          // it, and the similarity score is a small corner badge. The old layout
          // rendered the whole synopsis inline, growing each row so tall that
          // barely a cover was visible on screen (worse on TV, where you browse
          // by cover).
          : GridViewWidget(
              // Comfortable-grid ratios (cover plus one title line), matching
              // the library grid; a touch taller on TV so the focus ring and
              // title have room.
              childAspectRatio: isTv ? 0.60 : 0.642,
              itemCount: data!.length,
              itemBuilder: (context, index) {
                final rec = data![index];
                final title =
                    rec.titleEnglish ??
                    rec.titleRomaji ??
                    rec.titleNative ??
                    "";
                final coverUrl = rec.imgURLs.isNotEmpty
                    ? rec.imgURLs.first
                    : "";
                return CoverViewWidget(
                  // First cover autofocuses on TV so d-pad focus reaches the
                  // grid instead of getting stuck on the app bar.
                  autofocus: isTv && index == 0,
                  isComfortableGrid: true,
                  image: coverProvider(toImgUrl(coverUrl)),
                  bottomTextWidget: BottomTextWidget(
                    maxLines: 1,
                    text: title,
                    isComfortableGrid: true,
                  ),
                  onTap: () => context.push(
                    '/globalSearch',
                    extra: (title, widget.itemType),
                  ),
                  children: [
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _scoreBadge(context, rec.score),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _scoreBadge(BuildContext context, int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.primaryColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        "$score%",
        style: TextStyle(
          color: context.dynamicWhiteBlackColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
