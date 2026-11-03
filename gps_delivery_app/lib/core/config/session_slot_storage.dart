import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_slot_storage_stub.dart'
    if (dart.library.io) 'session_slot_storage_io.dart'
    as platform;

String? parseSessionSlotArg(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--session-slot=')) {
      final raw = arg.substring('--session-slot='.length).trim().toLowerCase();
      if (RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(raw)) {
        return raw;
      }
    }
  }
  return null;
}

FlutterAuthClientOptions buildSupabaseAuthOptions(String? slot) =>
    platform.buildSupabaseAuthOptions(slot);
