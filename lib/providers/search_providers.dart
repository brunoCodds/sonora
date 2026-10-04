import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/album.dart';
import '../data/models/artist.dart';
import '../data/models/playlist.dart';
import '../data/models/song.dart';
import 'library_providers.dart';
import 'playlist_providers.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

class SearchResults {
  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;

  const SearchResults({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;
}

/// Busca unificada usada pela tela "Buscar". Atualiza rapidamente pois
/// opera inteiramente sobre dados já carregados em memória.
final globalSearchResultsProvider = Provider<SearchResults>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return const SearchResults();

  final allSongs = ref.watch(libraryNotifierProvider).songs;
  final allPlaylists = ref.watch(playlistsNotifierProvider);

  final matchingSongs = allSongs
      .where((s) =>
          s.title.toLowerCase().contains(query) ||
          s.artist.toLowerCase().contains(query) ||
          s.album.toLowerCase().contains(query))
      .take(50)
      .toList();

  final albums = Album.groupSongs(allSongs)
      .where((a) =>
          a.name.toLowerCase().contains(query) ||
          a.artist.toLowerCase().contains(query))
      .take(30)
      .toList();

  final artists = Artist.groupSongs(allSongs)
      .where((a) => a.name.toLowerCase().contains(query))
      .take(30)
      .toList();

  final playlists = allPlaylists
      .where((p) => p.name.toLowerCase().contains(query))
      .take(30)
      .toList();

  return SearchResults(
    songs: matchingSongs,
    albums: albums,
    artists: artists,
    playlists: playlists,
  );
});
