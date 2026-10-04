import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'database_provider.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(databaseProvider));
});

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(databaseProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});
