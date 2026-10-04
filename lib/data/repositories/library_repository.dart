import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';
import '../models/song.dart';
import '../models/song_source.dart';

/// Responsável exclusivamente por ler/escrever músicas no banco local.
/// Não sabe nada sobre UI, importação de arquivos ou reprodução.
class LibraryRepository {
  final Database _db;

  LibraryRepository(AppDatabase database) : _db = database.db;

  /// Músicas "instaladas": as locais (`source = 'local'`) e as músicas da
  /// web que já foram baixadas (`source = 'youtube'` com `local_path`
  /// preenchido) — é a lista usada por Biblioteca, Álbuns e Artistas (o
  /// mesmo critério de [Song.isInstalled]).
  ///
  /// Uma música da web só entra aqui DEPOIS de instalada: quem clica em
  /// "instalar" espera encontrá-la na Biblioteca, e não só na pasta onde o
  /// arquivo foi salvo. Uma música da web ainda não baixada (só
  /// streaming) continua de fora — ela fica acessível por Favoritos,
  /// Playlists e pela busca, pra resultado de busca não poluir a coleção.
  List<Song> getAllSongs() {
    final result = _db.select(
      'SELECT * FROM songs '
      "WHERE source = 'local' OR (source = 'youtube' AND local_path IS NOT NULL) "
      'ORDER BY title COLLATE NOCASE',
    );
    return result.map(Song.fromMap).toList();
  }

  /// Todas as músicas favoritadas, locais e da web juntas — usada pela
  /// aba Favoritos, que é a única tela que precisa enxergar os dois
  /// mundos ao mesmo tempo.
  List<Song> getFavorites() {
    final result = _db.select(
      'SELECT * FROM songs WHERE is_favorite = 1 ORDER BY title COLLATE NOCASE',
    );
    return result.map(Song.fromMap).toList();
  }

  Song? getSongById(int id) {
    final result = _db.select('SELECT * FROM songs WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Song.fromMap(result.first);
  }

  bool existsByPath(String path) {
    final result =
        _db.select('SELECT 1 FROM songs WHERE path = ? LIMIT 1', [path]);
    return result.isNotEmpty;
  }

  /// Insere uma nova música ou atualiza os metadados se o caminho já
  /// existir na biblioteca (reimportação/atualização de tags).
  int upsertSong(Song song) {
    final existing =
        _db.select('SELECT id FROM songs WHERE path = ?', [song.path]);

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      final map = song.toMap();
      _db.execute(
        '''
        UPDATE songs SET
          title = ?, artist = ?, album = ?, album_artist = ?, genre = ?,
          year = ?, track_number = ?, duration_ms = ?, cover_path = ?
        WHERE id = ?
        ''',
        [
          map['title'],
          map['artist'],
          map['album'],
          map['album_artist'],
          map['genre'],
          map['year'],
          map['track_number'],
          map['duration_ms'],
          map['cover_path'],
          id,
        ],
      );
      return id;
    }

    final map = song.toMap();
    _db.execute(
      '''
      INSERT INTO songs
        (path, title, artist, album, album_artist, genre, year,
         track_number, duration_ms, cover_path, date_added)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        map['path'],
        map['title'],
        map['artist'],
        map['album'],
        map['album_artist'],
        map['genre'],
        map['year'],
        map['track_number'],
        map['duration_ms'],
        map['cover_path'],
        map['date_added'],
      ],
    );
    return _db.lastInsertRowId;
  }

  void setFavorite(int id, bool value) {
    _db.execute('UPDATE songs SET is_favorite = ? WHERE id = ?', [value ? 1 : 0, id]);
  }

  /// Insere ou atualiza uma música de origem `youtube` (resultado de
  /// busca, item de playlist importada, etc). Diferente de
  /// [upsertSong] (que deduplica por `path`, o caminho de um arquivo
  /// local), aqui a deduplicação é por [Song.remoteId] — a mesma
  /// música pode aparecer de novo em outra busca ou em outra playlist
  /// importada, e não deve virar uma segunda linha.
  ///
  /// Preserva `is_favorite` e `local_path` já existentes: reimportar
  /// (ex.: a mesma playlist de novo) não deve desfavoritar nem "perder"
  /// um download já feito.
  ///
  /// Também preserva `album`, `album_artist` e `track_number` já gravados
  /// quando o [song] novo não traz esses valores (álbum vazio / sem número
  /// de faixa): uma música instalada como parte de um álbum (ver
  /// `AlbumInstallNotifier`) não deve perder o álbum só porque o mesmo
  /// vídeo apareceu depois num resultado de busca comum, que não sabe de
  /// álbum nenhum.
  Song upsertWebSong(Song song) {
    assert(song.source == SongSource.youtube && song.remoteId != null);

    final existing = _db.select(
      'SELECT * FROM songs WHERE source = ? AND remote_id = ?',
      ['youtube', song.remoteId],
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final id = row['id'] as int;
      _db.execute(
        '''
        UPDATE songs SET
          title = ?, artist = ?,
          album = COALESCE(NULLIF(?, ''), album),
          album_artist = COALESCE(NULLIF(?, ''), album_artist),
          genre = ?,
          track_number = COALESCE(?, track_number),
          duration_ms = ?, cover_url = ?
        WHERE id = ?
        ''',
        [
          song.title,
          song.artist,
          song.album,
          song.albumArtist,
          song.genre,
          song.trackNumber,
          song.durationMs,
          song.coverUrl,
          id,
        ],
      );
      return Song.fromMap({...row, 'id': id});
    }

    final map = song.toMap();
    _db.execute(
      '''
      INSERT INTO songs
        (path, title, artist, album, album_artist, genre, year,
         track_number, duration_ms, cover_path, date_added, is_favorite,
         source, remote_id, cover_url, local_path)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        map['path'],
        map['title'],
        map['artist'],
        map['album'],
        map['album_artist'],
        map['genre'],
        map['year'],
        map['track_number'],
        map['duration_ms'],
        map['cover_path'],
        map['date_added'],
        map['is_favorite'],
        map['source'],
        map['remote_id'],
        map['cover_url'],
        map['local_path'],
      ],
    );
    final id = _db.lastInsertRowId;
    return song.copyWith(id: id);
  }

  /// Associa (ou remove, passando `null`) o arquivo baixado localmente
  /// para uma música da web. Ver `YoutubeDownloadService`.
  void setLocalPath(int id, String? path) {
    _db.execute('UPDATE songs SET local_path = ? WHERE id = ?', [path, id]);
  }

  /// Associa (ou remove, passando `null`) o arquivo de capa em cache local
  /// de uma música. Usado quando uma música da web é instalada: a capa
  /// (thumbnail) é baixada uma vez e guardada em disco, pra ela aparecer
  /// nas telas de álbum/artista e funcionar sem rede, como as capas
  /// extraídas de arquivos locais.
  void setCoverPath(int id, String? coverPath) {
    _db.execute('UPDATE songs SET cover_path = ? WHERE id = ?', [coverPath, id]);
  }

  void deleteSong(int id) {
    _db.execute('DELETE FROM songs WHERE id = ?', [id]);
  }

  void deleteSongs(Iterable<int> ids) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    _db.execute('DELETE FROM songs WHERE id IN ($placeholders)', ids.toList());
  }

  /// Limpa da biblioteca o que aponta pra um arquivo que não existe mais
  /// em disco.
  ///
  /// - Música local: a linha é removida do banco (o arquivo era a própria
  ///   música). Os ids removidos são devolvidos (útil para atualizar
  ///   fila/playlists em memória).
  /// - Música da web já instalada: a linha NÃO é removida — ela continua
  ///   existindo (pode ser tocada por streaming ou baixada de novo, e
  ///   segue nos favoritos/playlists); só perde o `local_path`, deixando
  ///   de contar como instalada e saindo da Biblioteca. Importante: o
  ///   `path` de uma música da web é uma chave sintética (`youtube:<id>`),
  ///   nunca um arquivo de verdade — por isso aqui se confere o
  ///   `local_path`, e não o `path`.
  List<int> pruneMissingFiles(bool Function(String path) fileExists) {
    final all = getAllSongs();
    final missingLocalIds = <int>[];
    for (final song in all) {
      if (song.source == SongSource.local) {
        if (!fileExists(song.path)) missingLocalIds.add(song.id);
      } else {
        final downloadedPath = song.localPath;
        if (downloadedPath != null && !fileExists(downloadedPath)) {
          setLocalPath(song.id, null);
        }
      }
    }
    deleteSongs(missingLocalIds);
    return missingLocalIds;
  }
}
