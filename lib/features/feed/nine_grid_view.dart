import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/utils/spring_page_route.dart';
import 'image_gallery_page.dart';

class NineGridView extends StatefulWidget {
  final CoolapkApi api;
  final List<GalleryImage> pics;
  final String statusId;
  final bool isDetail;
  final String? authorName;
  final String? authorId;
  final String? authorAvatar;
  final String? webpageCardCaption;

  const NineGridView({
    required this.api,
    super.key,
    required this.pics,
    required this.statusId,
    this.isDetail = false,
    this.authorName,
    this.authorId,
    this.authorAvatar,
    this.webpageCardCaption,
  });

  @override
  State<NineGridView> createState() => _NineGridViewState();
}

class _NineGridViewState extends State<NineGridView> {
  final Object _heroScope = Object();

  @override
  void initState() {
    super.initState();
    HdrImageDetector.notifier.addListener(_onHdrUpdated);
  }

  @override
  void dispose() {
    HdrImageDetector.notifier.removeListener(_onHdrUpdated);
    super.dispose();
  }

  void _onHdrUpdated() {
    if (mounted) setState(() {});
  }

  List<GalleryImage> get pics => widget.pics;
  String get statusId => widget.statusId;
  bool get isDetail => widget.isDetail;
  String? get authorName => widget.authorName;
  int get _visibleCount => !isDetail && pics.length > 9 ? 9 : pics.length;

  @override
  Widget build(BuildContext context) {
    if (pics.isEmpty) return const SizedBox.shrink();

    final count = _visibleCount;

    if (count == 1 || count == 2 || count == 4) {
      return _buildGrid(context, crossAxisCount: 2);
    }

    return _buildGrid(context, crossAxisCount: 3);
  }

  Widget _buildGrid(BuildContext context, {required int crossAxisCount}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = 7.0;
    final radius = BorderRadius.circular(12);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: 1.0,
      ),
      itemCount: _visibleCount,
      itemBuilder: (context, index) {
        final pic = pics[index];
        final thumbnail = Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: _buildImageContent(pic, colorScheme, cacheWidth: 450),
            ),
            if (pic.badgeText.isNotEmpty)
              Positioned(
                bottom: 4,
                right: 4,
                child: _buildBadge(pic.badgeText),
              ),
            if (!isDetail && pics.length > 9 && index == 8)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    key: ValueKey('media-overflow-$statusId'),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: radius,
                    ),
                    child: Text(
                      '+${pics.length - 9}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        return GestureDetector(
          onTap: () => _openMedia(context, index),
          child: ImageGalleryHeroThumbnail(
            scope: _heroScope,
            index: index,
            pic: pic,
            child: thumbnail,
          ),
        );
      },
    );
  }

  Widget _buildImageContent(
    GalleryImage pic,
    ColorScheme colorScheme, {
    int? cacheWidth,
    BoxFit fit = BoxFit.cover,
  }) {
    Widget networkImage(String url) {
      return ExtendedImage.network(
        url,
        headers: coolapkImageHeaders(url, api: widget.api),
        fit: fit,
        cache: true,
        cacheWidth: cacheWidth,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.loading) {
            return Container(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            );
          } else if (state.extendedImageLoadState == LoadState.completed) {
            HdrImageDetector.detectFromCache(
              url,
              headers: coolapkImageHeaders(url, api: widget.api),
            );
          }
          return null;
        },
      );
    }

    return networkImage(pic.previewUrl);
  }

  Widget _buildBadge(String text) {
    final isHdr = text == 'HDR';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
        border: isHdr
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 0.8,
              )
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: isHdr ? FontWeight.w900 : FontWeight.bold,
          letterSpacing: isHdr ? 0.4 : 0.0,
        ),
      ),
    );
  }

  void _openMedia(BuildContext context, int index) =>
      _openGallery(context, index);

  void _openGallery(BuildContext context, int initialIndex) {
    HapticFeedbackUtil.light();
    Navigator.of(context).push(
      PhysicsSpringGalleryRoute(
        child: ImageGalleryPage(
          api: widget.api,
          pics: pics,
          initialIndex: initialIndex,
          statusId: statusId,
          isDetail: isDetail,
          authorName: authorName,
          heroScope: _heroScope,
        ),
      ),
    );
  }
}
