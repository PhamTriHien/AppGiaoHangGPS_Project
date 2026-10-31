import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> signInCloudGoogle(SupabaseClient client) async {
  await client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: Uri.base.resolve('/').toString(),
  );
}
