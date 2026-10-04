/// Extensões de arquivo de áudio suportadas pelo Sonora.
///
/// O player (media_kit/libmpv) já é capaz de reproduzir todos esses
/// formatos nativamente. Esta lista controla apenas quais arquivos o
/// importador/scanner de pastas reconhece como música.
///
/// Para adicionar suporte a um novo formato no futuro, basta incluir a
/// extensão aqui — nenhuma outra parte do código depende de uma lista
/// fixa de formatos.
class SupportedFormats {
  SupportedFormats._();

  static const List<String> audioExtensions = [
    'mp3',
    'flac',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'opus',
    // webm é o formato mais comum que "-f bestaudio" devolve para vídeos
    // do YouTube (Opus dentro de um contêiner WebM) — as músicas baixadas
    // pelo Sonora rotineiramente chegam nesse formato.
    'webm',
  ];

  static bool isSupported(String path) {
    final lower = path.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex == -1) return false;
    final ext = lower.substring(dotIndex + 1);
    return audioExtensions.contains(ext);
  }
}
