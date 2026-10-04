import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';
import '../models/playlist.dart';

class PlaylistRepository {
  final Database _db;

  PlaylistRepository(AppDatabase database) : _db = database.db;

  List<Playlist> getAllPlaylists() {
    final rows = _db.select('SELECT * FROM playlists ORDER BY created_at DESC');
    return rows.map((row) {
      final songIds = _songIdsFor(row['id'] as int);
      return Playlist(
        id: row['id'] as int,
        name: row['name'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        songIds: songIds,
      );
    }).toList();
  }

  List<int> _songIdsFor(int playlistId) {
    final rows = _db.select(
      'SELECT song_id FROM playlist_songs WHERE playlist_id = ? ORDER BY position ASC',
      [playlistId],
    );
    return rows.map((r) => r['song_id'] as int).toList();
  }

  Playlist createPlaylist(String name) {
    final now = DateTime.now();
    _db.execute(
      'INSERT INTO playlists (name, created_at) VALUES (?, ?)',
      [name, now.millisecondsSinceEpoch],
    );
    final id = _db.lastInsertRowId;
    return Playlist(id: id, name: name, createdAt: now, songIds: const []);
  }

  void renamePlaylist(int id, String newName) {
    _db.execute('UPDATE playlists SET name = ? WHERE id = ?', [newName, id]);
  }

  void deletePlaylist(int id) {
    _db.execute('DELETE FROM playlists WHERE id = ?', [id]);
  }

  void addSongToPlaylist(int playlistId, int songId) {
    final alreadyThere = _db.select(
      'SELECT 1 FROM playlist_songs WHERE playlist_id = ? AND song_id = ?',
      [playlistId, songId],
    );
    if (alreadyThere.isNotEmpty) return;

    final maxPositionRow = _db.select(
      'SELECT COALESCE(MAX(position), -1) as max_pos FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    final nextPosition = (maxPositionRow.first['max_pos'] as int) + 1;
    _db.execute(
      'INSERT INTO playlist_songs (playlist_id, song_id, position) VALUES (?, ?, ?)',
      [playlistId, songId, nextPosition],
    );
  }

  void addSongsToPlaylist(int playlistId, Iterable<int> songIds) {
    for (final id in songIds) {
      addSongToPlaylist(playlistId, id);
    }
  }

  void removeSongFromPlaylist(int playlistId, int songId) {
    _db.execute(
      'DELETE FROM playlist_songs WHERE playlist_id = ? AND song_id = ?',
      [playlistId, songId],
    );
    _resequence(playlistId);
  }

  /// Persiste uma nova ordem completa de músicas na playlist (drag & drop).
  void reorderPlaylistSongs(int playlistId, List<int> orderedSongIds) {
    for (var i = 0; i < orderedSongIds.length; i++) {
      _db.execute(
        'UPDATE playlist_songs SET position = ? WHERE playlist_id = ? AND song_id = ?',
        [i, playlistId, orderedSongIds[i]],
      );
    }
  }

  void _resequence(int playlistId) {
    final ids = _songIdsFor(playlistId);
    reorderPlaylistSongs(playlistId, ids);
  }
}
