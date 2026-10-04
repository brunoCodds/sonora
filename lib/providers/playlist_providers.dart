import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/playlist.dart';
import '../data/models/song.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';
import 'repository_providers.dart';

class PlaylistsNotifier extends StateNotifier<List<Playlist>> {
  final PlaylistRepository _repository;
  final LibraryRepository _library;

  PlaylistsNotifier(this._repository, this._library) : super(const []) {
    _reload();
  }

  void _reload() {
    state = _repository.getAllPlaylists();
  }

  /// Resolve os ids de uma playlist para os objetos [Song] atuais,
  /// ignorando silenciosamente músicas que tenham sido removidas da
  /// biblioteca.
  List<Song> songsFor(Playlist playlist) {
    return playlist.songIds
        .map((id) => _library.getSongById(id))
        .whereType<Song>()
        .toList();
  }

  Playlist create(String name) {
    final playlist = _repository.createPlaylist(name);
    _reload();
    return playlist;
  }

  void rename(int id, String newName) {
    _repository.renamePlaylist(id, newName);
    _reload();
  }

  void delete(int id) {
    _repository.deletePlaylist(id);
    _reload();
  }

  void addSong(int playlistId, int songId) {
    _repository.addSongToPlaylist(playlistId, songId);
    _reload();
  }

  void addSongs(int playlistId, Iterable<int> songIds) {
    _repository.addSongsToPlaylist(playlistId, songIds);
    _reload();
  }

  void removeSong(int playlistId, int songId) {
    _repository.removeSongFromPlaylist(playlistId, songId);
    _reload();
  }

  void reorder(int playlistId, List<int> orderedSongIds) {
    _repository.reorderPlaylistSongs(playlistId, orderedSongIds);
    _reload();
  }
}

final playlistsNotifierProvider =
    StateNotifierProvider<PlaylistsNotifier, List<Playlist>>((ref) {
  return PlaylistsNotifier(
    ref.watch(playlistRepositoryProvider),
    ref.watch(libraryRepositoryProvider),
  );
});
