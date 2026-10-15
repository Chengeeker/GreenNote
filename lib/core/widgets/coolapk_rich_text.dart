import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../network/coolapk_api.dart';
import '../../features/shared/api_list_page.dart';
import 'cached_network_image.dart';

/// Coolapk emotion shortcode to CDN PNG code mapping.
const Map<String, String> coolapkEmotionMap = {
  '滑稽': 'c-huaji',
  'doge': 'c-doge',
  '傲慢': 'c-aoman',
  'doge喝茶': 'c-dogehechi',
  'doge笑哭': 'c-dogexiaoku',
  '二哈': 'c-erha',
  '流泪': 'c-liulei',
  '捂脸': 'c-wulian',
  '笑哭': 'c-xiaoku',
  '发怒': 'c-fanu',
  '白眼': 'c-baiyan',
  '爱心': 'c-aixin',
  '心碎': 'c-xinsui',
  'OK': 'c-ok',
  'ok': 'c-ok',
  '强': 'c-qiang',
  '弱': 'c-ruo',
  '色': 'c-se',
  '吐舌': 'c-tushe',
  '可怜': 'c-kelian',
  '可爱': 'c-keai',
  '发呆': 'c-fadai',
  '吃瓜': 'c-chigua',
  '绿帽': 'c-lvmao',
  '酷安': 'c-kuan',
  '酷安绿帽': 'c-kuanlvmao',
  '欢呼': 'c-huanhu',
  '托腮': 'c-tuosai',
  'cos滑稽': 'c-coshuaji',
  '斗鸡眼滑稽': 'c-doujiyanhuaji',
  '墨镜滑稽': 'c-mojinghuaji',
  '受虐滑稽': 'c-shounuehuaji',
  '流汗滑稽': 'c-liuhanhuaji',
  '黑线': 'c-heixian',
  '坏笑': 'c-huaixiao',
  '微笑': 'c-weixiao',
  '无奈': 'c-wunai',
  '无语': 'c-wuyu',
  '委屈': 'c-weiqu',
  '疑问': 'c-yiwen',
  '阴险': 'c-yinxian',
  '再见': 'c-zaijian',
  '喷血': 'c-penxue',
  '吐血': 'c-penxue',
  '撇嘴': 'c-piezui',
  '害羞': 'c-haixiu',
  '抠鼻': 'c-koubi',
  '菜刀': 'c-caidao',
  '玫瑰': 'c-meigui',
  '凋谢': 'c-diaoxie',
  '抱拳': 'c-baoquan',
  '鄙视': 'c-bishi',
  '酷币': 'c-coolb',
  '酷': 'c-ku',
  '惊讶': 'c-jingya',
  '难过': 'c-nanguo',
  '亲亲': 'c-qinqin',
  '睡': 'c-shui',
  '皱眉': 'c-zhoumei',
  '呵呵': 'c-hehe',
  '哈哈哈': 'c-hahaha',
  '呲牙': 'c-ciya',
  '汗': 'c-han',
  '嘿哈': 'c-heiha',
  '喝酒': 'c-hejiu',
  '红药丸': 'c-hongyaowan',
  '绿药丸': 'c-lvyaowan',
  '火把': 'c-huoba',
  '机智': 'c-jizhi',
  '喵喵': 'c-miaomiao',
  '耐克嘴': 'c-naikezui',
  '牛逼': 'c-nb',
  'NB': 'c-nb',
  'nb': 'c-nb',
  '喷': 'c-pen',
  '噗': 'c-pu',
  'PY交易': 'c-pyjiaoyi',
  'py交易': 'c-pyjiaoyi',
  'qqdoge': 'c-qqdoge',
  '微微一笑': 'c-weiweiyixiao',
  '我最美': 'c-wozuimei',
  '捂嘴笑': 'c-wuzuixiao',
  '笑眼': 'c-xiaoyan',
  '耶': 'c-ye',
  '二哈盯': 'c-erhading',
  '原谅他': 'c-dogeyuanliangta',
  '苦笑': 'c-wulian',
  '捂脸哭': 'c-xiaoku',
};

/// CDN host for Coolapk emotion icons.
const String _coolapkEmotionCdn = 'https://coolemotion.netlify.app/source/png/';

/// Returns the emotion image URL for a given emotion name, or null if not found.
String? getCoolapkEmotionUrl(String name) {
  final cleanName = name.startsWith('[') && name.endsWith(']')
      ? name.substring(1, name.length - 1)
      : name;
  final code =
      coolapkEmotionMap[cleanName] ??
      coolapkEmotionMap[cleanName.toLowerCase()];
  if (code == null) return null;
  return '$_coolapkEmotionCdn$code.png';
}

/// Rich text widget for Coolapk posts & comments.
///
/// Features:
/// 1. Emoticon parsing: renders `[滑稽]` as inline images with high clarity.
/// 2. Topic tag parsing: renders `#话题#` as clickable primary-colored links leading to [TopicPage].
/// 3. Web URL parsing: opens web links externally.
/// 4. Preserves pure [Text] widget optimization when no markup is found.
class CoolapkRichText extends StatelessWidget {
  const CoolapkRichText({
    required this.api,
    required this.text,
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.onTapTag,
  });

  final CoolapkApi api;
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final void Function(String tag)? onTapTag;

  static final RegExp _markupRegex = RegExp(
    r'(\[([^\]\n]+)\])|(#[^#\n\r\t]+#)|(https?:\/\/[^\s]+)',
  );

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Text('', style: style);
    }

    // Optimization: if text has no bracket, hash, or http, return standard Text directly
    if (!text.contains('[') && !text.contains('#') && !text.contains('http')) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final tagColor = theme.colorScheme.primary;

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in _markupRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: text.substring(lastIndex, match.start),
            style: baseStyle,
          ),
        );
      }

      final fullMatch = match.group(0)!;

      // 1. Emotion: [xxx]
      if (fullMatch.startsWith('[') && fullMatch.endsWith(']')) {
        final emotionName = fullMatch.substring(1, fullMatch.length - 1);
        final emotionUrl = getCoolapkEmotionUrl(emotionName);

        if (emotionUrl != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: CachedNetworkImage(
                  emotionUrl,
                  width: (baseStyle.fontSize ?? 16) * 1.25,
                  height: (baseStyle.fontSize ?? 16) * 1.25,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(fullMatch, style: baseStyle),
                ),
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: fullMatch, style: baseStyle));
        }
      }
      // 2. Topic tag: #xxx#
      else if (fullMatch.startsWith('#') &&
          fullMatch.endsWith('#') &&
          fullMatch.length > 2) {
        final tagName = fullMatch.substring(1, fullMatch.length - 1);
        spans.add(
          TextSpan(
            text: fullMatch,
            style: baseStyle.copyWith(
              color: tagColor,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (onTapTag != null) {
                  onTapTag!(tagName);
                } else {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => TopicPage(api: api, tag: tagName),
                    ),
                  );
                }
              },
          ),
        );
      }
      // 3. Web URL: http://... or https://...
      else if (fullMatch.startsWith('http://') ||
          fullMatch.startsWith('https://')) {
        spans.add(
          TextSpan(
            text: fullMatch,
            style: baseStyle.copyWith(
              color: tagColor,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                if (await canLaunchUrlString(fullMatch)) {
                  await launchUrlString(
                    fullMatch,
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
          ),
        );
      } else {
        spans.add(TextSpan(text: fullMatch, style: baseStyle));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: baseStyle));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
