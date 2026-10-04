import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as p;

import '../../data/models/song.dart';

/// Resultado da leitura de metadados de um arquivo, antes de ser
/// persistido no banco (ainda não tem `id`/`dateAdded` definitivos).
class ParsedTrack {
  final String path;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int? year;
  final int? trackNumber;
  final int durationMs;
  final String? coverPath;

  ParsedTrack({
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
  });

  Song toSong({int id = 0, DateTime? dateAdded}) {
    return Song(
      id: id,
      path: path,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
      durationMs: durationMs,
      coverPath: coverPath,
      dateAdded: dateAdded ?? DateTime.now(),
    );
  }
}

/// Lê metadados (título, artista, álbum, capa, etc.) de arquivos de
/// áudio usando a biblioteca `audiotags` (baseada na crate Rust `lofty`,
/// com bom suporte a mp3/flac/wav/ogg/m4a).
class MetadataService {
  /// Cache em memória do caminho de capa já extraída para uma
  /// combinação álbum+artista, evitando escrever o mesmo arquivo de
  /// capa repetidas vezes durante a importação de um álbum inteiro.
  final Map<String, String> _coverCache = {};

  Future<ParsedTrack> readTrack(String filePath, Directory coversDir) async {
    Tag? tag;
    try {
      tag = await AudioTags.read(filePath);
    } catch (_) {
      tag = null;
    }

    final fileNameNoExt = p.basenameWithoutExtension(filePath);

    final title = (tag?.title?.trim().isNotEmpty ?? false)
        ? tag!.title!.trim()
        : fileNameNoExt;
    final artist = tag?.trackArtist?.trim() ?? '';
    final album = tag?.album?.trim() ?? '';
    final albumArtist = tag?.albumArtist?.trim() ?? '';
    final genre = tag?.genre?.trim() ?? '';
    final year = tag?.year;
    final trackNumber = tag?.trackNumber;
    final durationMs = ((tag?.duration ?? 0) * 1000);

    String? coverPath;
    final pictures = tag?.pictures;
    if (pictures != null && pictures.isNotEmpty) {
      coverPath = await _extractCover(
        pictures.first.bytes,
        album: album,
        albumArtist: albumArtist,
        coversDir: coversDir,
      );
    }

    return ParsedTrack(
      path: filePath,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
      durationMs: durationMs,
      coverPath: coverPath,
    );
  }

  Future<String> _extractCover(
    List<int> bytes, {
    required String album,
    required String albumArtist,
    required Directory coversDir,
  }) async {
    final cacheKey = '$albumArtist|$album';
    final cached = _coverCache[cacheKey];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }

    final safeKey = cacheKey.hashCode.toRadixString(16);
    final file = File(p.join(coversDir.path, '$safeKey.cover'));

    if (!file.existsSync() || file.lengthSync() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }

    _coverCache[cacheKey] = file.path;
    return file.path;
  }
}
