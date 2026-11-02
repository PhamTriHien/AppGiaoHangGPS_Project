import 'package:supabase_flutter/supabase_flutter.dart';

const googleOAuthQueryParams = <String, String>{'prompt': 'select_account'};

Future<void> signInCloudGoogle(SupabaseClient client) async {
  await client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: Uri.base.resolve('/').toString(),
    queryParams: googleOAuthQueryParams,
  );
}
