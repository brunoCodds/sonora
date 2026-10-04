import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/file_import/file_import_service.dart';
import '../services/metadata/metadata_service.dart';
import '../services/security/secure_credentials_store.dart';
import '../services/spotify/spotify_client.dart';
import '../services/web_music/playlist_import_service.dart';
import '../services/youtube/youtube_client.dart';

final metadataServiceProvider = Provider<MetadataService>((ref) {
  return MetadataService();
});

final fileImportServiceProvider = Provider<FileImportService>((ref) {
  return FileImportService();
});

final secureCredentialsStoreProvider = Provider<SecureCredentialsStore>((ref) {
  return SecureCredentialsStore();
});

/// Cliente do YouTube (busca, playlists, streams e download) —
/// `FutureProvider` porque a criação confere que o `yt-dlp.exe`
/// empacotado existe (ver `YtDlpProcess.resolveExecutable`); isso é
/// praticamente instantâneo (não baixa nada em runtime), mas manter como
/// `FutureProvider` evita qualquer mudança nos lugares que já leem isto
/// como um `AsyncValue` (`.future`, `.isLoading`, etc.). `keepAlive`
/// porque não há razão para descartar entre navegações.
final youtubeClientProvider = FutureProvider<YoutubeClient>((ref) async {
  ref.keepAlive();
  return YoutubeClient.create();
});

final spotifyClientProvider = Provider<SpotifyClient>((ref) {
  return SpotifyClient(ref.watch(secureCredentialsStoreProvider));
});

final playlistImportServiceProvider = FutureProvider<PlaylistImportService>((ref) async {
  final youtube = await ref.watch(youtubeClientProvider.future);
  final spotify = ref.watch(spotifyClientProvider);
  return PlaylistImportService(youtube, spotify);
});
