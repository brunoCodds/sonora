import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/song.dart';
import '../data/models/song_source.dart';
import '../data/repositories/library_repository.dart';
import 'repository_providers.dart';

/// Lista de músicas favoritadas, locais e da web juntas — a fonte de
/// dados por trás da aba Favoritos.
///
/// Existe separado de `LibraryNotifier` porque `LibraryState.songs`
/// (usada por Biblioteca/Álbuns/Artistas) só contém músicas locais
/// (`source = local`) de propósito — a aba Favoritos é a única tela do
/// app que precisa enxergar local e web ao mesmo tempo.
///
/// É recarregada sempre que um favorito muda (ver
/// `LibraryNotifier.toggleFavorite`), então nunca precisa ser observada
/// "manualmente" — só `ref.watch(favoritesNotifierProvider)`.
class FavoritesNotifier extends StateNotifier<List<Song>> {
  final LibraryRepository _repository;

  FavoritesNotifier(this._repository) : super(const []) {
    loadFromDb();
  }

  void loadFromDb() {
    state = _repository.getFavorites();
  }

  List<Song> get localFavorites =>
      state.where((s) => s.source == SongSource.local).toList();

  List<Song> get webFavorites =>
      state.where((s) => s.source == SongSource.youtube).toList();
}

final favoritesNotifierProvider =
    StateNotifierProvider<FavoritesNotifier, List<Song>>((ref) {
  return FavoritesNotifier(ref.watch(libraryRepositoryProvider));
});
