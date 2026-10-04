import 'song.dart';
import 'album.dart';

/// Assim como [Album], um artista é uma agregação derivada das músicas,
/// não uma tabela própria.
class Artist {
  final String name;
  final List<Song> songs;

  Artist({required this.name, required this.songs});

  List<Album> get albums => Album.groupSongs(songs);

  String? get coverPath {
    for (final song in songs) {
      if (song.coverPath != null) return song.coverPath;
    }
    return null;
  }

  static List<Artist> groupSongs(List<Song> songs) {
    final Map<String, Artist> artists = {};
    for (final song in songs) {
      final name =
          song.groupArtist.isNotEmpty ? song.groupArtist : 'Artista desconhecido';
      artists.putIfAbsent(name, () => Artist(name: name, songs: []));
      artists[name]!.songs.add(song);
    }
    final result = artists.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }
}
