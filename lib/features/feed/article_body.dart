import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/coolapk_url_handler.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import 'image_gallery_page.dart';

typedef ArticlePart = ({String type, String text, String url, String caption});

List<ArticlePart> parseArticleParts(Map<String, dynamic> data) {
  final parts = <ArticlePart>[];
  String imageUrl(dynamic value) {
    final url = normalizeCoolapkImageUrl('${value ?? ''}');
    final uri = Uri.tryParse(url);
    return uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? url
        : '';
  }

  void text(String value) {
    if (value.trim().isNotEmpty) {
      parts.add((type: 'text', text: value.trim(), url: '', caption: ''));
    }
  }

  void rich(String source) {
    final pending = StringBuffer();
    void flush() {
      text(pending.toString());
      pending.clear();
    }

    void visit(dom.Node node) {
      if (node is! dom.Element) {
        if (node is dom.Text) pending.write(node.data);
        return;
      }
      if (['script', 'style'].contains(node.localName)) return;
      if (node.localName == 'img') {
        final alt = node.attributes['alt'] ?? '';
        if (RegExp(r'^\[[^\]]+\]$').hasMatch(alt)) {
          pending.write(alt);
          return;
        }
        final url = imageUrl(
          node.attributes['data-original'] ??
              node.attributes['data-src'] ??
              node.attributes['src'],
        );
        if (url.isNotEmpty) {
          flush();
          parts.add((type: 'image', text: '', url: url, caption: ''));
        }
      } else if (node.querySelector('img') == null) {
        pending.write(node.outerHtml);
        if (['p', 'div', 'figure', 'section'].contains(node.localName)) {
          pending.writeln();
        }
      } else {
        for (final child in node.nodes) {
          visit(child);
        }
        if (['p', 'div', 'figure', 'section'].contains(node.localName)) {
          pending.writeln();
        }
      }
    }

    for (final node in html.parseFragment(source).nodes) {
      visit(node);
    }
    flush();
  }

  dynamic raw = data['message_raw_output'] ?? data['messageRawOutput'];
  if (raw is String && raw.isNotEmpty && raw != 'null') {
    try {
      raw = jsonDecode(raw);
    } on FormatException {
      raw = null;
    }
  }
  if (raw is List) {
    for (final item in raw.whereType<Map>()) {
      final type = '${item['type'] ?? ''}';
      if (type == 'text') {
        rich('${item['message'] ?? item['text'] ?? ''}');
      } else if (type == 'image') {
        final url = imageUrl(item['url']);
        if (url.isNotEmpty) {
          parts.add((
            type: 'image',
            text: '',
            url: url,
            caption: '${item['description'] ?? ''}',
          ));
        }
      } else if (type == 'shareUrl') {
        final url = '${item['url'] ?? ''}'.trim();
        final uri = Uri.tryParse(url);
        if (uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          parts.add((
            type: 'link',
            text: '${item['title'] ?? url}',
            url: url,
            caption: '',
          ));
        }
      }
    }
    if (parts.isNotEmpty) return parts;
  }
  final source = '${data['message'] ?? ''}';
  if (RegExp(r'<img\b', caseSensitive: false).hasMatch(source)) rich(source);
  return parts;
}

class ArticleBody extends StatelessWidget {
  const ArticleBody({
    super.key,
    required this.api,
    required this.feed,
    required this.parts,
  });
  final CoolapkApi api;
  final CoolapkFeed feed;
  final List<ArticlePart> parts;

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final part in parts)
        if (part.type == 'image')
          GalleryImage(part.url, raw: feed.pictureMetadata[part.url]),
    ];
    var imageIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in parts.indexed)
          Padding(
            key: ValueKey('article-part-${entry.$1}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: switch (entry.$2.type) {
              'image' => _image(context, entry.$2, images, imageIndex++),
              'link' => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                tileColor: Theme.of(context).colorScheme.surfaceContainer,
                leading: const Icon(Icons.link),
                title: Text(entry.$2.text),
                onTap: () =>
                    CoolapkUrlHandler.handleUrl(context, api, entry.$2.url),
              ),
              _ => CoolapkRichText(
                api: api,
                text: entry.$2.text,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.65,
                  letterSpacing: .15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            },
          ),
      ],
    );
  }

  Widget _image(
    BuildContext context,
    ArticlePart part,
    List<GalleryImage> images,
    int index,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        label: '查看图文正文图片',
        child: GestureDetector(
          onTap: () {
            HapticFeedbackUtil.light();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageGalleryPage(
                  api: api,
                  pics: images,
                  initialIndex: index,
                  statusId: '${feed.id}:article',
                  isDetail: true,
                  authorName: feed.username,
                ),
              ),
            );
          },
          child: CachedNetworkImage(
            part.url,
            headers: coolapkImageHeaders(part.url, api: api),
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 100,
              child: Center(child: Text('图片加载失败')),
            ),
          ),
        ),
      ),
      if (part.caption.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: CoolapkRichText(
            api: api,
            text: part.caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );
}
