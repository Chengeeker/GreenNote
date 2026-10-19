import 'dart:convert';

/// Coolapk's NEC challenge; a blank field uses the validate Cookie protocol.
class CoolapkCaptchaChallenge {
  const CoolapkCaptchaChallenge(this.id, this.field);
  final String id;
  final String field;
  bool get isValid =>
      RegExp(r'^[a-zA-Z0-9]{16,64}$').hasMatch(id) &&
      (field.isEmpty || RegExp(r'^_[a-zA-Z0-9_]{1,63}$').hasMatch(field));

  static CoolapkCaptchaChallenge? fromResponse(Map<String, dynamic> root) {
    if (root['messageStatus'] != 'err_request_captcha_v2') return null;
    dynamic extra = root['messageExtra'] ?? root['extra'] ?? root;
    if (extra is String) {
      try {
        extra = jsonDecode(extra);
      } on FormatException {
        return null;
      }
    }
    if (extra is! Map) return null;
    final id = extra['captchaId'];
    final field = extra['captchaField'] ?? '_v2_post_token';
    if (extra['captchaType'] != null && extra['captchaType'] != 'NEC') {
      return null;
    }
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9]{16,64}$').hasMatch(id) ||
        field is! String ||
        (field.isNotEmpty &&
            !RegExp(r'^_[a-zA-Z0-9_]{1,63}$').hasMatch(field))) {
      return null;
    }
    return CoolapkCaptchaChallenge(id, field);
  }

  String? proof(String validate) {
    if (!isValid ||
        validate.isEmpty ||
        validate.length > 8192 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(validate)) {
      return null;
    }
    return 'NEC:${id.substring(0, 8)}:$validate';
  }
}
