import 'song.dart';

/// Um álbum não é uma tabela própria no banco: é uma agregação das
/// músicas que compartilham (album, albumArtist). Isso evita duplicar
/// dados e mantém a fonte de verdade única nas músicas/metadados.
class Album {
  final String name;
  final String artist;
  final List<Song> songs;

  Album({required this.name, required this.artist, required this.songs});

  String? get coverPath {
    for (final song in songs) {
      if (song.coverPath != null) return song.coverPath;
    }
    return null;
  }

  int? get year {
    for (final song in songs) {
      if (song.year != null) return song.year;
    }
    return null;
  }

  Duration get totalDuration => songs.fold(
        Duration.zero,
        (total, song) => total + song.duration,
      );

  List<Song> get sortedSongs {
    final list = List<Song>.from(songs);
    list.sort((a, b) {
      final aTrack = a.trackNumber ?? 0;
      final bTrack = b.trackNumber ?? 0;
      if (aTrack != bTrack) return aTrack.compareTo(bTrack);
      return a.title.compareTo(b.title);
    });
    return list;
  }

  String get key => '$name|$artist';

  /// Agrupa uma lista de músicas em álbuns.
  static List<Album> groupSongs(List<Song> songs) {
    final Map<String, Album> albums = {};
    for (final song in songs) {
      final albumName = song.album.isNotEmpty ? song.album : 'Álbum desconhecido';
      final albumArtist = song.groupArtist.isNotEmpty
          ? song.groupArtist
          : 'Artista desconhecido';
      final key = '$albumName|$albumArtist';
      albums.putIfAbsent(
        key,
        () => Album(name: albumName, artist: albumArtist, songs: []),
      );
      albums[key]!.songs.add(song);
    }
    final result = albums.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }
}
