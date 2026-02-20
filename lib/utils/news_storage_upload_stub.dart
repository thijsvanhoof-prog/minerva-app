import 'package:supabase_flutter/supabase_flutter.dart';

/// Web: geen ondersteuning voor Storage-upload (geen dart:io File).
Future<String?> uploadNewsImageToStorage(
  SupabaseClient client,
  String path,
  String filePath,
) async {
  return null;
}
