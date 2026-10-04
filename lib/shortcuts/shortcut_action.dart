/// Cada ação de player que pode ser disparada por um atalho de teclado e,
/// a partir de agora, reatribuída pelo usuário em Configurações.
enum ShortcutAction {
  playPause,
  next,
  previous,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  mute,
}

extension ShortcutActionLabel on ShortcutAction {
  /// Nome amigável mostrado na tela de configurações.
  String get label {
    switch (this) {
      case ShortcutAction.playPause:
        return 'Reproduzir / pausar';
      case ShortcutAction.next:
        return 'Próxima música';
      case ShortcutAction.previous:
        return 'Música anterior';
      case ShortcutAction.seekForward:
        return 'Avançar 5 segundos';
      case ShortcutAction.seekBackward:
        return 'Voltar 5 segundos';
      case ShortcutAction.volumeUp:
        return 'Aumentar volume';
      case ShortcutAction.volumeDown:
        return 'Diminuir volume';
      case ShortcutAction.mute:
        return 'Ativar / desativar mudo';
    }
  }
}
