/// Referência a uma faixa lida de uma playlist do Spotify — só
/// metadados (o Spotify nunca entra na parte de reprodução, ver
/// `PlaylistImportService`).
///
/// Efêmero: usado só durante a importação, para achar a música
/// correspondente no YouTube. Nunca vira uma [Song] diretamente.
class SpotifyTrackRef {
  final String name;
  final List<String> artists;
  final Duration? duration;

  const SpotifyTrackRef({
    required this.name,
    required this.artists,
    required this.duration,
  });

  /// Nomes dos artistas juntos, usado para montar a query de busca no
  /// YouTube (ex.: "Song Name Artist One Artist Two").
  String get artistsJoined => artists.join(' ');

  /// Texto de busca a ser usado no YouTube para achar esta faixa.
  String get searchQuery => '$name $artistsJoined'.trim();
}
