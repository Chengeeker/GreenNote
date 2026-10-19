import 'dart:convert';

class OfficialDeviceIdentity {
  static const storageKey = 'greennote.official_device_code';

  static bool _validId(String id) =>
      !const ['null', 'undefined'].contains(id.toLowerCase()) &&
      RegExp(r'^[A-Za-z0-9_+/.=-]{8,4096}$').hasMatch(id);

  static String parse(String text) {
    if (text.length > 32768) throw const FormatException('复制内容过长，请重新从官方酷安复制');
    final matches = RegExp(
      r'^[ \t]*ShuzlmID[ \t]*[:：][ \t]*([^\r\n]*)$',
      multiLine: true,
      caseSensitive: false,
    ).allMatches(text.replaceAll('\uFEFF', '')).toList();
    if (matches.length != 1) {
      throw const FormatException(
        '未找到唯一的 ShuzlmID，请在官方同一页面累计点击“复制 OAID”5次，再复制完整内容',
      );
    }
    final id = matches.single.group(1)!.trim();
    if (!_validId(id)) throw const FormatException('数盟 ID 为空或格式不正确，请在官方酷安重新复制');
    return id;
  }

  static List<String>? fields(String code) {
    if (code.isEmpty || code.length > 16384) return null;
    try {
      final values = utf8
          .decode(
            base64Decode(base64.normalize(code.split('').reversed.join())),
          )
          .split(';');
      if (values.length == 9 &&
          _validId(values.first) &&
          values
              .skip(1)
              .every(
                (value) =>
                    value.length <= 256 &&
                    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value),
              )) {
        return values;
      }
    } on FormatException {
      // Older GreenNote installs use an unencoded UUID; preserve it for rollback.
    }
    return null;
  }

  static String encode(
    String id, {
    required String previous,
    Map<String, dynamic> profile = const {},
  }) {
    if (!_validId(id)) throw const FormatException('数盟 ID 格式不正确');
    String property(String name) {
      final value = profile[name];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > 256 ||
          RegExp(r'[;\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FormatException('无法读取设备机型参数，未修改设备标识');
      }
      return ' ${value.trim()}';
    }

    final values =
        fields(previous) ??
        [
          id,
          ' ',
          ' ',
          ' ',
          property('manufacturer'),
          property('brand'),
          property('model'),
          property('display'),
          ' null',
        ];
    values[0] = id;
    return base64Encode(utf8.encode(values.join(';')))
        .split('')
        .reversed
        .join()
        .replaceAll('=', '');
  }
}
