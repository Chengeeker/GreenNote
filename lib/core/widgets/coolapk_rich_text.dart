import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../network/coolapk_api.dart';
import '../utils/coolapk_url_handler.dart';
import '../../features/shared/api_list_page.dart';
import 'cached_network_image.dart';

/// Coolapk emotion shortcode to CDN PNG code mapping.
const Map<String, String> coolapkEmotionMap = {
  // 经典滑稽与二哈
  '滑稽': 'c-huaji',
  '手动滑稽': 'c-huaji',
  'cos滑稽': 'c-coshuaji',
  '斗鸡眼滑稽': 'c-doujiyanhuaji',
  '墨镜滑稽': 'c-mojinghuaji',
  '受虐滑稽': 'c-shounuehuaji',
  '流汗滑稽': 'c-liuhanhuaji',
  '滑稽吃瓜': 'c-huajichigua',
  'doge': 'c-doge',
  'doge喝茶': 'c-dogehechi',
  'doge笑哭': 'c-dogexiaoku',
  '二哈': 'c-erha',
  '二哈盯': 'c-erhading',
  '原谅他': 'c-dogeyuanliangta',
  'qqdoge': 'c-qqdoge',

  // 基础表情
  '微笑': 'c-weixiao',
  '笑': 'c-weixiao',
  '呲牙': 'c-ciya',
  '大笑': 'c-hahaha',
  '哈哈哈': 'c-hahaha',
  '笑哭': 'c-xiaoku',
  '捂脸哭': 'c-xiaoku',
  '捂脸': 'c-wulian',
  '苦笑': 'c-wulian',
  '偷笑': 'c-wuzuixiao',
  '捂嘴笑': 'c-wuzuixiao',
  '微微一笑': 'c-weiweiyixiao',
  '笑眼': 'c-xiaoyan',
  '呵呵': 'c-hehe',
  '嘿哈': 'c-heiha',
  '欢呼': 'c-huanhu',
  '托腮': 'c-tuosai',
  '可爱': 'c-keai',
  '可怜': 'c-kelian',
  '发呆': 'c-fadai',
  '吃瓜': 'c-chigua',
  '害羞': 'c-haixiu',
  '调皮': 'c-tiaopi',
  '吐舌': 'c-tushe',
  '色': 'c-se',
  '亲亲': 'c-qinqin',
  '亲': 'c-qinqin',
  '傲慢': 'c-aoman',
  '白眼': 'c-baiyan',
  '黑线': 'c-heixian',
  '坏笑': 'c-huaixiao',
  '阴险': 'c-yinxian',
  '无奈': 'c-wunai',
  '无语': 'c-wuyu',
  '委屈': 'c-weiqu',
  '疑问': 'c-yiwen',
  '皱眉': 'c-zhoumei',
  '再见': 'c-zaijian',
  '睡': 'c-shui',
  '睡觉': 'c-shui',
  '困': 'c-kun',
  '哈欠': 'c-haqian',
  '难过': 'c-nanguo',
  '衰': 'c-shuai',
  '流泪': 'c-liulei',
  '哭': 'c-liulei',
  '泪': 'c-liulei',
  '快哭了': 'c-kuaikule',
  '汗': 'c-han',
  '流汗': 'c-han',
  '狂汗': 'c-kuanghan',
  '发怒': 'c-fanu',
  '怒': 'c-fanu',
  '喷血': 'c-penxue',
  '吐血': 'c-penxue',
  '喷': 'c-pen',
  '噗': 'c-pu',
  '撇嘴': 'c-piezui',
  '抠鼻': 'c-koubi',
  '鄙视': 'c-bishi',
  '惊讶': 'c-jingya',
  '惊喜': 'c-jingya',
  '惊吓': 'c-jingxia',
  '吓': 'c-xia',
  '晕': 'c-yun',
  '抓狂': 'c-zhuakuang',
  '吐': 'c-tu',
  '闭嘴': 'c-bizui',
  '打脸': 'c-dalian',
  '生病': 'c-shengbing',
  '思考': 'c-sikao',
  '奋斗': 'c-fengdou',
  '饥饿': 'c-jie',
  '骷髅': 'c-kulou',
  '便便': 'c-bianbian',
  '炸弹': 'c-zhadan',
  '菜刀': 'c-caidao',
  '刀': 'c-caidao',

  // 动作与手势
  'OK': 'c-ok',
  'ok': 'c-ok',
  '强': 'c-qiang',
  '赞': 'c-qiang',
  '点赞': 'c-qiang',
  '好评': 'c-qiang',
  '给力': 'c-geili',
  '弱': 'c-ruo',
  '踩': 'c-ruo',
  '差评': 'c-ruo',
  '抱拳': 'c-baoquan',
  '握手': 'c-woshou',
  '胜利': 'c-ye',
  '耶': 'c-ye',
  '鼓掌': 'c-guzhang',
  '加油': 'c-jiayou',
  '打call': 'c-dacall',
  '打Call': 'c-dacall',
  '打CALL': 'c-dacall',
  '互粉': 'c-hufen',

  // 酷安特色
  '绿帽': 'c-lvmao',
  '酷安': 'c-kuan',
  '酷安绿帽': 'c-kuanlvmao',
  '酷币': 'c-coolb',
  '酷': 'c-ku',
  '牛逼': 'c-nb',
  'NB': 'c-nb',
  'nb': 'c-nb',
  'PY交易': 'c-pyjiaoyi',
  'py交易': 'c-pyjiaoyi',
  '耐克嘴': 'c-naikezui',
  '我最美': 'c-wozuimei',
  '机智': 'c-jizhi',
  '喵喵': 'c-miaomiao',
  '红药丸': 'c-hongyaowan',
  '绿药丸': 'c-lvyaowan',
  '火把': 'c-huoba',
  '火': 'c-huoba',

  // 物品、饮食与情感
  '爱心': 'c-aixin',
  '心': 'c-aixin',
  '心碎': 'c-xinsui',
  '玫瑰': 'c-meigui',
  '凋谢': 'c-diaoxie',
  '喝酒': 'c-hejiu',
  '啤酒': 'c-pijiu',
  '喝茶': 'c-hecha',
  '咖啡': 'c-kafei',
  '可乐': 'c-kele',
  '奶茶': 'c-naicha',
  '蛋糕': 'c-dangao',
  '西瓜': 'c-xigua',
  '红包': 'c-hongbao',
  '礼物': 'c-liwu',
  '太阳': 'c-taiyang',
  '月亮': 'c-yueliang',
  '猪头': 'c-zhutou',
  '爆米花': 'c-chibaomihua',
  '吃爆米花': 'c-chibaomihua',
  '柠檬': 'c-ningmeng',
  '酸了': 'c-suanle',
  '酸': 'c-ningmeng',
  '柠檬精': 'c-ningmeng',
  '鸽子': 'c-gezi',
  '咕咕咕': 'c-gugugu',
  '鸽了': 'c-gezi',
  '锦鲤': 'c-jinli',
  '保佑': 'c-baoyou',
  '暴富': 'c-baofu',
  '发财': 'c-baofu',
  '中奖': 'c-zhongjiang',

  // 流行梗与网络热词
  '妙啊': 'c-miaoa',
  '芜湖': 'c-wuhu',
  '起飞': 'c-qifei',
  '芜湖起飞': 'c-wuhuqifei',
  '太南了': 'c-tainanle',
  '太难了': 'c-tainanle',
  '太秃然了': 'c-taituranle',
  '秃然': 'c-taituranle',
  '裂开': 'c-liekai',
  '我裂开了': 'c-woliekaile',
  '小丑': 'c-xiaochou',
  '绝绝子': 'c-juejuezi',
  'yyds': 'c-yyds',
  'YYDS': 'c-yyds',
  '蚌埠住了': 'c-bengbuzhule',
  '破防': 'c-pofang',
  '躺平': 'c-tangping',
  '摆烂': 'c-bailan',
  'emo': 'c-emo',
  'EMO': 'c-emo',
  '芭比Q': 'c-babiq',
  '急了': 'c-jile',
  '麻了': 'c-male',
  '不愧是你': 'c-bukuishini',
  '战术后仰': 'c-zhanshuhouyang',
  '看戏': 'c-kanxi',
  '冷酷': 'c-lengku',
  '傲娇': 'c-aojiao',
  '尴尬': 'c-ganga',

  // 货币系列
  '1元': 'c-1yuan',
  '2元': 'c-2yuan',
  '5元': 'c-5yuan',
  '10元': 'c-10yuan',
  '20元': 'c-20yuan',
  '50元': 'c-50yuan',
  '100元': 'c-100yuan',
  '1毛': 'c-1mao',
  '2毛': 'c-2mao',
  '5毛': 'c-5mao',
  '1分': 'c-1fen',
  '2分': 'c-2fen',
  '5分': 'c-5fen',
};

/// Fallback map to convert text emoticons to Unicode Emojis when image fails or is unavailable.
const Map<String, String> _unicodeEmojiFallback = {
  '滑稽': '😏',
  '手动滑稽': '😏',
  'cos滑稽': '😏',
  'doge': '🐶',
  '二哈': '🐶',
  '流泪': '😭',
  '哭': '😭',
  '泪': '😭',
  '捂脸': '🤦',
  '笑哭': '😂',
  '捂脸哭': '😂',
  '发怒': '😡',
  '怒': '😡',
  '白眼': '🙄',
  '爱心': '❤️',
  '心': '❤️',
  '心碎': '💔',
  'OK': '👌',
  'ok': '👌',
  '强': '👍',
  '赞': '👍',
  '点赞': '👍',
  '弱': '👎',
  '踩': '👎',
  '差评': '👎',
  '色': '😍',
  '吐舌': '😛',
  '调皮': '😜',
  '可怜': '🥺',
  '可爱': '🥰',
  '发呆': '😶',
  '吃瓜': '🍉',
  '欢呼': '🎉',
  '托腮': '🤔',
  '思考': '🤔',
  '坏笑': '😈',
  '微笑': '🙂',
  '笑': '😄',
  '大笑': '😆',
  '哈哈哈': '🤣',
  '无奈': '😮‍💨',
  '无语': '😑',
  '委屈': '🥺',
  '疑问': '❓',
  '阴险': '😏',
  '再见': '👋',
  '害羞': '😳',
  '玫瑰': '🌹',
  '凋谢': '🥀',
  '抱拳': '👊',
  '握手': '🤝',
  '胜利': '✌️',
  '耶': '✌️',
  '酷': '😎',
  '惊讶': '😲',
  '难过': '😢',
  '亲亲': '😘',
  '睡': '😴',
  '睡觉': '😴',
  '皱眉': '😟',
  '呲牙': '😁',
  '汗': '😅',
  '流汗': '😓',
  '喝酒': '🍺',
  '啤酒': '🍺',
  '咖啡': '☕',
  '红药丸': '💊',
  '绿药丸': '💊',
  '火把': '🔥',
  '火': '🔥',
  '机智': '💡',
  '喵喵': '🐱',
  '红包': '🧧',
  '礼物': '🎁',
  '蛋糕': '🎂',
  '西瓜': '🍉',
  '便便': '💩',
  '炸弹': '💣',
  '菜刀': '🔪',
  '刀': '🔪',
  '太阳': '☀️',
  '月亮': '🌙',
  '猪头': '🐷',
  '鼓掌': '👏',
  '加油': '💪',
  '裂开': '💔',
  '小丑': '🤡',
  '柠檬': '🍋',
  '酸了': '🍋',
  '酸': '🍋',
  '鸽子': '🕊️',
  '锦鲤': '🐟',
  '暴富': '💰',
  '发财': '💰',
  '酷币': '🪙',
  '1元': '🪙',
  '100元': '💵',
};

/// Resolves an emotion shortcode string into the Coolapk CDN resource code (e.g., 'c-huaji').
String? getCoolapkEmotionCode(String name) {
  final cleanName = name.startsWith('[') && name.endsWith(']')
      ? name.substring(1, name.length - 1)
      : name;

  final direct =
      coolapkEmotionMap[cleanName] ??
      coolapkEmotionMap[cleanName.toLowerCase()];
  if (direct != null) return direct;

  // Check if it's numeric 1..100
  final numVal = int.tryParse(cleanName);
  if (numVal != null && numVal >= 1 && numVal <= 100) {
    return 'c-$numVal';
  }
  if (cleanName.startsWith('c-')) {
    final subNum = int.tryParse(cleanName.substring(2));
    if (subNum != null && subNum >= 1 && subNum <= 100) {
      return cleanName;
    }
  }
  return null;
}

/// Returns the primary emotion image URL for a given emotion name, or null if not found.
String? getCoolapkEmotionUrl(String name) {
  final code = getCoolapkEmotionCode(name);
  if (code == null) return null;
  return 'https://coolemotion.netlify.app/source/png/$code.png';
}

/// Robust emotion image with multi-CDN fallback and Unicode emoji graceful degradation.
class _EmotionImage extends StatefulWidget {
  const _EmotionImage({
    required this.code,
    required this.size,
    required this.fallbackText,
    required this.textStyle,
    this.unicodeFallback,
  });

  final String code;
  final double size;
  final String fallbackText;
  final TextStyle textStyle;
  final String? unicodeFallback;

  @override
  State<_EmotionImage> createState() => _EmotionImageState();
}

class _EmotionImageState extends State<_EmotionImage> {
  int _cdnIndex = 0;

  static const List<String> _cdnBases = [
    'https://coolemotion.netlify.app/source/png/',
    'https://cdn.jsdelivr.net/gh/Coolapk-Dev/Coolapk-Emotion/source/png/',
    'https://fastly.jsdelivr.net/gh/Coolapk-Dev/Coolapk-Emotion/source/png/',
  ];

  @override
  Widget build(BuildContext context) {
    if (_cdnIndex >= _cdnBases.length) {
      if (widget.unicodeFallback != null) {
        return Text(widget.unicodeFallback!, style: widget.textStyle);
      }
      return Text(widget.fallbackText, style: widget.textStyle);
    }

    final url = '${_cdnBases[_cdnIndex]}${widget.code}.png';

    return CachedNetworkImage(
      url,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        if (_cdnIndex < _cdnBases.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _cdnIndex++;
              });
            }
          });
        }
        if (widget.unicodeFallback != null) {
          return Text(widget.unicodeFallback!, style: widget.textStyle);
        }
        return Text(widget.fallbackText, style: widget.textStyle);
      },
    );
  }
}

/// Rich text widget for Coolapk posts & comments.
///
/// Features:
/// 1. Emoticon parsing: renders `[滑稽]` as inline images with high clarity and multi-CDN fallback.
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
    this.prefixSpans = const [],
    this.suffixSpans = const [],
  });

  final CoolapkApi api;
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final void Function(String tag)? onTapTag;
  final List<InlineSpan> prefixSpans;
  final List<InlineSpan> suffixSpans;

  static final RegExp _markupRegex = RegExp(
    r'(\[([^\]\n]+)\])|(#[^#\n\r\t]+#)|(https?:\/\/[^\s]+)',
  );

  static final Map<String, List<_RichToken>> _tokenCache = {};
  static const int _maxCacheEntries = 500;

  static List<_RichToken> _tokenize(String text) {
    final cached = _tokenCache[text];
    if (cached != null) return cached;

    final tokens = <_RichToken>[];
    var lastIndex = 0;

    for (final match in _markupRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        tokens.add(
          _RichToken(
            type: _RichTokenType.text,
            text: text.substring(lastIndex, match.start),
          ),
        );
      }

      final fullMatch = match.group(0)!;

      // 1. Emotion: [xxx]
      if (fullMatch.startsWith('[') && fullMatch.endsWith(']')) {
        final emotionName = fullMatch.substring(1, fullMatch.length - 1);
        final emotionCode = getCoolapkEmotionCode(emotionName);
        final unicodeFallback =
            _unicodeEmojiFallback[emotionName] ??
            _unicodeEmojiFallback[emotionName.toLowerCase()];
        tokens.add(
          _RichToken(
            type: _RichTokenType.emotion,
            text: fullMatch,
            emotionCode: emotionCode,
            unicodeFallback: unicodeFallback,
          ),
        );
      }
      // 2. Topic tag: #xxx#
      else if (fullMatch.startsWith('#') &&
          fullMatch.endsWith('#') &&
          fullMatch.length > 2) {
        final tagName = fullMatch.substring(1, fullMatch.length - 1);
        tokens.add(
          _RichToken(
            type: _RichTokenType.tag,
            text: fullMatch,
            tagName: tagName,
          ),
        );
      }
      // 3. Web URL: http://... or https://...
      else if (fullMatch.startsWith('http://') ||
          fullMatch.startsWith('https://')) {
        tokens.add(
          _RichToken(
            type: _RichTokenType.url,
            text: fullMatch,
          ),
        );
      } else {
        tokens.add(
          _RichToken(
            type: _RichTokenType.text,
            text: fullMatch,
          ),
        );
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      tokens.add(
        _RichToken(
          type: _RichTokenType.text,
          text: text.substring(lastIndex),
        ),
      );
    }

    if (_tokenCache.length >= _maxCacheEntries) {
      _tokenCache.clear();
    }
    _tokenCache[text] = tokens;
    return tokens;
  }

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && prefixSpans.isEmpty && suffixSpans.isEmpty) {
      return Text('', style: style);
    }

    // Optimization: if text has no bracket, hash, or http, return standard Text directly
    if (prefixSpans.isEmpty &&
        suffixSpans.isEmpty &&
        !text.contains('[') &&
        !text.contains('#') &&
        !text.contains('http')) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final tagColor = theme.colorScheme.primary;

    final spans = <InlineSpan>[...prefixSpans];
    final tokens = _tokenize(text);

    for (final token in tokens) {
      switch (token.type) {
        case _RichTokenType.text:
          spans.add(TextSpan(text: token.text, style: baseStyle));
          break;
        case _RichTokenType.emotion:
          if (token.emotionCode != null) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: _EmotionImage(
                    code: token.emotionCode!,
                    size: (baseStyle.fontSize ?? 16) * 1.25,
                    fallbackText: token.text,
                    textStyle: baseStyle,
                    unicodeFallback: token.unicodeFallback,
                  ),
                ),
              ),
            );
          } else if (token.unicodeFallback != null) {
            spans.add(
              TextSpan(
                text: token.unicodeFallback!,
                style: baseStyle.copyWith(
                  fontSize: (baseStyle.fontSize ?? 16) * 1.15,
                ),
              ),
            );
          } else {
            spans.add(TextSpan(text: token.text, style: baseStyle));
          }
          break;
        case _RichTokenType.tag:
          final tagName = token.tagName ?? '';
          spans.add(
            TextSpan(
              text: token.text,
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
          break;
        case _RichTokenType.url:
          final url = token.text;
          spans.add(
            TextSpan(
              text: url,
              style: baseStyle.copyWith(
                color: tagColor,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await CoolapkUrlHandler.handleUrl(context, api, url);
                },
            ),
          );
          break;
      }
    }
    spans.addAll(suffixSpans);

    return Text.rich(
      TextSpan(children: spans),
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

enum _RichTokenType { text, emotion, tag, url }

class _RichToken {
  const _RichToken({
    required this.type,
    required this.text,
    this.emotionCode,
    this.unicodeFallback,
    this.tagName,
  });

  final _RichTokenType type;
  final String text;
  final String? emotionCode;
  final String? unicodeFallback;
  final String? tagName;
}
