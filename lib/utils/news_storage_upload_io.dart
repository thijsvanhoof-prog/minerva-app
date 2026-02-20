import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// iOS/Android/Desktop: upload bestand naar Storage, retourneer public URL.
Future<String?> uploadNewsImageToStorage(
  SupabaseClient client,
  String path,
  String filePath,
) async {
  await client.storage.from('news-images').upload(path, File(filePath));
  return client.storage.from('news-images').getPublicUrl(path);
}
