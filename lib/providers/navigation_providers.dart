import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Seções principais da barra lateral.
///
/// Optamos por navegação simples baseada em estado (IndexedStack +
/// providers), em vez de um pacote de rotas como go_router: para um
/// app desktop de janela única com uma sidebar fixa, essa é a solução
/// mais simples e confiável — sem URLs, sem deep-linking necessário.
enum AppSection {
  library,
  playlists,
  albums,
  artists,
  favorites,
  search,
  profile,
  settings,
}

final currentSectionProvider = StateProvider<AppSection>((ref) {
  return AppSection.library;
});

/// Quando não nulo, a seção "Playlists" mostra o detalhe da playlist
/// em vez da lista.
final selectedPlaylistIdProvider = StateProvider<int?>((ref) => null);

/// Quando não nulo, a seção "Álbuns" mostra as músicas do álbum
/// selecionado (chave = "nome|artista", ver [Album.key]).
final selectedAlbumKeyProvider = StateProvider<String?>((ref) => null);

/// Quando não nulo, a seção "Artistas" mostra as músicas/álbuns do
/// artista selecionado.
final selectedArtistNameProvider = StateProvider<String?>((ref) => null);

/// Controla se o painel lateral da fila de reprodução está visível.
final queuePanelOpenProvider = StateProvider<bool>((ref) => false);
