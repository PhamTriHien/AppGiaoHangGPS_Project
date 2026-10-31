import 'dart:convert';

// Only the publishable key belongs in the app. Database/server credentials do not.
const defaultSupabaseUrl = 'https://yvnbfurazjbhbopahtmx.supabase.co';
const defaultSupabasePublishableKey =
    'sb_publishable_GGR7kRKyUpBeYvgtGj5tDw_cDqwXflB';

({String url, String publicKey}) resolveCloudConnection({
  Map<String, dynamic> saved = const {},
  String buildUrl = const String.fromEnvironment('SUPABASE_URL'),
  String buildPublicKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
}) {
  final savedUrl = saved['supabaseUrl'];
  final savedKey = saved['supabaseAnonKey'];
  final hasSaved =
      (savedUrl is String && savedUrl.trim().isNotEmpty) ||
      (savedKey is String && savedKey.trim().isNotEmpty);
  final hasBuild =
      buildUrl.trim().isNotEmpty || buildPublicKey.trim().isNotEmpty;
  final url = hasSaved
      ? (savedUrl is String ? savedUrl.trim() : '')
      : hasBuild
      ? buildUrl.trim()
      : defaultSupabaseUrl;
  final key = hasSaved
      ? (savedKey is String ? savedKey.trim() : '')
      : hasBuild
      ? buildPublicKey.trim()
      : defaultSupabasePublishableKey;
  final parsed = Uri.tryParse(url);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.hasQuery ||
      parsed.hasFragment ||
      !['', '/'].contains(parsed.path) ||
      key.isEmpty) {
    throw const FormatException(
      'Cấu hình Supabase cần URL HTTPS và public key đầy đủ.',
    );
  }
  var public = key.startsWith('sb_publishable_');
  if (!public && key.split('.').length == 3) {
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(key.split('.')[1]))),
      );
      public = claims is Map && claims['role'] == 'anon';
    } catch (_) {}
  }
  if (!public) {
    throw const FormatException('Ứng dụng chỉ chấp nhận publishable/anon key.');
  }
  return (url: parsed.replace(path: '').toString(), publicKey: key);
}
