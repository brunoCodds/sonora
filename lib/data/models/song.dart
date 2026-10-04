import 'song_source.dart';

/// Representa uma música — da biblioteca local ou da web (YouTube).
///
/// Classe imutável e simples de propósito: evitamos geração de código
/// (freezed/json_serializable) para manter o projeto compilável sem
/// nenhuma etapa extra de `build_runner`.
///
/// Uma música de [source] `youtube` também é uma linha normal da
/// tabela `songs` (ver `AppDatabase`/`LibraryRepository`) — isso é o
/// que permite que favoritos, playlists e fila funcionem para ela sem
/// nenhum código separado. A diferença é só de onde os bytes de áudio
/// vêm na hora de tocar:
/// - `path`, para uma música `youtube`, guarda uma chave estável
///   (`youtube:<videoId>`), NUNCA a URL de streaming de verdade (essa
///   expira em algumas horas e precisa ser resolvida de novo a cada
///   reprodução — ver `YoutubeClient.getAudioStreamUrl`).
/// - `localPath`, quando presente, é o arquivo baixado de verdade em
///   disco (ver `YoutubeDownloadService`) — nesse caso a reprodução usa
///   o arquivo diretamente, sem precisar resolver stream nem de
///   internet.
class Song {
  final int id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int? year;
  final int? trackNumber;
  final int durationMs;

  /// Caminho, em disco, para a capa extraída do arquivo (cache local).
  /// `null` quando o arquivo não possui capa embutida (comum) ou quando
  /// a música é da web e ainda não teve a capa baixada (ver [coverUrl]).
  final String? coverPath;

  final DateTime dateAdded;

  final bool isFavorite;

  /// De onde a música veio. Ver o comentário da classe.
  final SongSource source;

  /// ID do vídeo no YouTube, quando [source] é `youtube`. `null` para
  /// músicas locais.
  final String? remoteId;

  /// URL remota da capa (thumbnail do YouTube), quando [source] é
  /// `youtube`. Diferente de [coverPath]: essa é sempre carregada pela
  /// rede (`Image.network`), nunca cacheada em disco nesta versão.
  final String? coverUrl;

  /// Caminho, em disco, do arquivo de áudio baixado para uma música da
  /// web (ver `YoutubeDownloadService`). `null` enquanto ela só existe
  /// como stream. Sempre `null` para músicas locais (o próprio [path]
  /// já é o arquivo, nesse caso).
  final String? localPath;

  const Song({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    required this.year,
    required this.trackNumber,
    required this.durationMs,
    required this.coverPath,
    required this.dateAdded,
    this.isFavorite = false,
    this.source = SongSource.local,
    this.remoteId,
    this.coverUrl,
    this.localPath,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  /// Artista usado para agrupar por artista (prioriza albumArtist quando
  /// definido, já que é mais consistente para álbuns colaborativos).
  String get groupArtist => albumArtist.isNotEmpty ? albumArtist : artist;

  /// Verdadeiro quando a música tem um arquivo de áudio de verdade em
  /// disco pronto pra tocar sem rede — seja porque é local, seja porque
  /// é uma música da web que já foi baixada (ver [localPath]).
  bool get isInstalled => source == SongSource.local || localPath != null;

  Song copyWith({
    int? id,
    String? path,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? trackNumber,
    int? durationMs,
    String? coverPath,
    bool clearCover = false,
    DateTime? dateAdded,
    bool? isFavorite,
    SongSource? source,
    String? remoteId,
    String? coverUrl,
    String? localPath,
    bool clearLocalPath = false,
  }) {
    return Song(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      durationMs: durationMs ?? this.durationMs,
      coverPath: clearCover ? null : (coverPath ?? this.coverPath),
      dateAdded: dateAdded ?? this.dateAdded,
      isFavorite: isFavorite ?? this.isFavorite,
      source: source ?? this.source,
      remoteId: remoteId ?? this.remoteId,
      coverUrl: coverUrl ?? this.coverUrl,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
    );
  }

  factory Song.fromMap(Map<String, Object?> map) {
    return Song(
      id: map['id'] as int,
      path: map['path'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      albumArtist: map['album_artist'] as String,
      genre: map['genre'] as String,
      year: map['year'] as int?,
      trackNumber: map['track_number'] as int?,
      durationMs: map['duration_ms'] as int,
      coverPath: map['cover_path'] as String?,
      dateAdded:
          DateTime.fromMillisecondsSinceEpoch(map['date_added'] as int),
      // As colunas abaixo podem não existir ainda em bancos muito
      // antigos que por algum motivo não passaram pela migração em
      // AppDatabase — os `??`/fromName aqui são só uma rede de
      // segurança extra, não deveria ser necessário na prática.
      isFavorite: (map['is_favorite'] as int?) == 1,
      source: SongSource.fromName(map['source'] as String?),
      remoteId: map['remote_id'] as String?,
      coverUrl: map['cover_url'] as String?,
      localPath: map['local_path'] as String?,
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      'path': path,
      'title': title,
      'artist': artist,
      'album': album,
      'album_artist': albumArtist,
      'genre': genre,
      'year': year,
      'track_number': trackNumber,
      'duration_ms': durationMs,
      'cover_path': coverPath,
      'date_added': dateAdded.millisecondsSinceEpoch,
      'is_favorite': isFavorite ? 1 : 0,
      'source': source.name,
      'remote_id': remoteId,
      'cover_url': coverUrl,
      'local_path': localPath,
    };
    if (includeId) map['id'] = id;
    return map;
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
