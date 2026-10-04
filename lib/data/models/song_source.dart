/// De onde uma [Song] veio.
///
/// `local` é o comportamento histórico do app (arquivo importado do
/// disco). `youtube` cobre tanto uma música encontrada direto na busca
/// da web quanto uma importada de uma playlist do YouTube ou do
/// Spotify — nesse último caso, o Spotify só forneceu os metadados
/// (nome/artista) usados para achar a faixa correspondente no YouTube;
/// a reprodução em si sempre acontece via YouTube.
enum SongSource {
  local,
  youtube;

  static SongSource fromName(String? name) {
    return SongSource.values.firstWhere(
      (source) => source.name == name,
      orElse: () => SongSource.local,
    );
  }
}
