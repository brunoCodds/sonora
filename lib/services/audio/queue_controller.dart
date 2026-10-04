import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/shuffle_utils.dart';
import '../../data/models/repeat_mode.dart';
import '../../data/models/song.dart';
import '../../data/models/song_source.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/service_providers.dart';
import '../youtube/ytdlp_process.dart';
import 'audio_player_service.dart';

class QueueState {
  final List<Song> queue;
  final int currentIndex;
  final RepeatMode repeatMode;
  final bool shuffleEnabled;

  /// Ordem original (sem embaralhar), usada para restaurar quando o
  /// shuffle é desativado.
  final List<Song> originalOrder;

  /// Mensagem de erro transiente da última tentativa de reprodução (ex.:
  /// stream do YouTube indisponível). `null` quando a última tentativa
  /// deu certo. Pensado para a UI mostrar um snackbar/banner, não para
  /// persistir em lugar nenhum.
  final String? playbackError;

  const QueueState({
    this.queue = const [],
    this.currentIndex = -1,
    this.repeatMode = RepeatMode.off,
    this.shuffleEnabled = false,
    this.originalOrder = const [],
    this.playbackError,
  });

  Song? get currentSong =>
      (currentIndex >= 0 && currentIndex < queue.length)
          ? queue[currentIndex]
          : null;

  List<Song> get upcoming =>
      currentIndex >= 0 && currentIndex + 1 < queue.length
          ? queue.sublist(currentIndex + 1)
          : const [];

  bool get hasNext =>
      repeatMode != RepeatMode.off || currentIndex < queue.length - 1;

  bool get hasPrevious => currentIndex > 0;

  QueueState copyWith({
    List<Song>? queue,
    int? currentIndex,
    RepeatMode? repeatMode,
    bool? shuffleEnabled,
    List<Song>? originalOrder,
    String? playbackError,
    bool clearPlaybackError = false,
  }) {
    return QueueState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      originalOrder: originalOrder ?? this.originalOrder,
      playbackError:
          clearPlaybackError ? null : (playbackError ?? this.playbackError),
    );
  }
}

/// Controla a fila de reprodução: qual música está tocando, o que vem a
/// seguir, shuffle e modo de repetição. Delega a reprodução em si ao
/// [AudioPlayerService].
class QueueController extends StateNotifier<QueueState> {
  final AudioPlayerService _audio;
  final SettingsRepository _settings;
  final LibraryRepository _library;

  /// Usado só para ler `youtubeClientProvider` de forma preguiçosa
  /// dentro de [_openSong] (só quando uma música da web precisa
  /// resolver um stream) — mesmo padrão que `LibraryNotifier` já usa
  /// para acessar outros providers a partir de um StateNotifier.
  final Ref _ref;

  StreamSubscription<bool>? _completedSub;

  /// Verdadeiro assim que algum arquivo já foi de fato aberto no
  /// [AudioPlayerService] nesta sessão. A fila/índice podem estar
  /// restaurados do disco (ver [_restorePersistedState]) sem que isso
  /// seja verdade ainda — o motor de áudio (media_kit/libmpv) só é
  /// inicializado na primeira ação de reprodução do usuário, não mais
  /// automaticamente ao abrir o app.
  bool _engineLoaded = false;

  QueueController(this._audio, this._settings, this._library, this._ref)
      : super(const QueueState()) {
    _restorePersistedState();
    _completedSub = _audio.completed.listen(_onCompletedChanged);
  }

  void _restorePersistedState() {
    final shuffle = _settings.getBool(AppConstants.keyShuffleEnabled);
    final repeat =
        RepeatMode.fromName(_settings.getString(AppConstants.keyRepeatMode));
    final savedIds = _settings.getIntList(AppConstants.keyLastQueue);
    final savedIndex =
        _settings.getInt(AppConstants.keyLastQueueIndex, fallback: -1);

    if (savedIds.isEmpty) {
      state = state.copyWith(shuffleEnabled: shuffle, repeatMode: repeat);
      return;
    }

    final songs = savedIds
        .map((id) => _library.getSongById(id))
        .whereType<Song>()
        .toList();

    if (songs.isEmpty) {
      state = state.copyWith(shuffleEnabled: shuffle, repeatMode: repeat);
      return;
    }

    state = state.copyWith(
      queue: songs,
      originalOrder: songs,
      currentIndex: savedIndex.clamp(0, songs.length - 1),
      shuffleEnabled: shuffle,
      repeatMode: repeat,
    );

    // Propositalmente NÃO chama _audio.openAndPlay aqui.
    //
    // Isso já chegou a abrir o media_kit/libmpv logo na inicialização do
    // app (antes de qualquer interação do usuário), e essa é exatamente
    // a janela em que o crash "Callback invoked after it has been
    // deleted" vinha acontecendo nos testes — sem nenhum
    // redimensionamento envolvido, só de abrir o app com uma fila salva.
    //
    // A fila e o índice continuam restaurados acima (o usuário ainda vê
    // a última música/fila ao abrir a tela do player), só que agora o
    // motor de áudio só é inicializado quando o usuário efetivamente
    // manda tocar algo (toque num item da fila/biblioteca ou aperta
    // play). `currentPosition`/`currentDuration` ficam em zero até lá,
    // o que é esperado: nada está carregado no player ainda.
  }

  void _onCompletedChanged(bool completed) {
    if (!completed) return;
    if (state.repeatMode == RepeatMode.one) {
      _playCurrent(restartFromZero: true);
      return;
    }
    _advance(userInitiated: false);
  }

  /// Substitui a fila inteira e começa a tocar a partir de [startIndex]
  /// (índice relativo a [songs], não à fila já embaralhada).
  Future<void> setQueueAndPlay(
    List<Song> songs, {
    int startIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final startSong = songs[startIndex.clamp(0, songs.length - 1)];

    List<Song> playOrder = songs;
    if (state.shuffleEnabled) {
      playOrder = ShuffleUtils.shuffle(songs, keepFirst: startSong);
    }

    state = state.copyWith(
      queue: playOrder,
      originalOrder: songs,
      currentIndex: playOrder.indexOf(startSong),
    );
    _persistQueue();
    await _playCurrent(restartFromZero: true);
  }

  Future<void> addToQueue(Song song) async {
    final newQueue = [...state.queue, song];
    final newOriginal = [...state.originalOrder, song];
    final wasEmpty = state.queue.isEmpty;
    state = state.copyWith(queue: newQueue, originalOrder: newOriginal);
    _persistQueue();
    if (wasEmpty) {
      state = state.copyWith(currentIndex: 0);
      await _playCurrent(restartFromZero: true);
    }
  }

  Future<void> addSongsToQueue(List<Song> songs) async {
    for (final song in songs) {
      await addToQueue(song);
    }
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;
    final removedSong = state.queue[index];
    final newQueue = [...state.queue]..removeAt(index);
    final newOriginal = [...state.originalOrder]..remove(removedSong);

    var newIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newIndex -= 1;
    } else if (index == state.currentIndex) {
      // A música removida era a atual: mantém o índice (próxima música
      // ocupa a posição), mas não força troca de faixa em reprodução.
    }
    state = state.copyWith(
      queue: newQueue,
      originalOrder: newOriginal,
      currentIndex: newIndex.clamp(-1, newQueue.length - 1),
    );
    _persistQueue();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    // oldIndex/newIndex já vêm com o índice final correto (não precisa
    // do ajuste manual "-1 quando oldIndex < newIndex" que a API antiga
    // onReorder exigia) — este método agora é alimentado por
    // onReorderItem em queue_panel.dart, que já faz essa correção
    // internamente antes de chamar aqui.
    if (oldIndex == newIndex) return;
    final newQueue = [...state.queue];
    final item = newQueue.removeAt(oldIndex);
    final insertIndex = newIndex;
    newQueue.insert(insertIndex, item);

    var currentIndex = state.currentIndex;
    if (oldIndex == currentIndex) {
      currentIndex = insertIndex;
    } else if (oldIndex < currentIndex && insertIndex >= currentIndex) {
      currentIndex -= 1;
    } else if (oldIndex > currentIndex && insertIndex <= currentIndex) {
      currentIndex += 1;
    }

    state = state.copyWith(queue: newQueue, currentIndex: currentIndex);
    _persistQueue();
  }

  void clearQueue() {
    _audio.stop();
    state = const QueueState();
    _persistQueue();
  }

  /// Reflete na fila em memória um favorito alternado em outro lugar
  /// (ver `LibraryNotifier.toggleFavorite`) — a fila guarda sua própria
  /// cópia dos `Song`, montada quando a reprodução começou, então uma
  /// mudança feita só no banco/na lista da biblioteca não apareceria
  /// aqui sozinha. Não persiste nada por conta própria: quem já chamou
  /// isso (o `LibraryNotifier`) é quem cuidou do banco.
  void updateSongFavorite(int songId, bool value) {
    List<Song> patch(List<Song> songs) => [
          for (final s in songs)
            if (s.id == songId) s.copyWith(isFavorite: value) else s,
        ];
    state = state.copyWith(
      queue: patch(state.queue),
      originalOrder: patch(state.originalOrder),
    );
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    state = state.copyWith(currentIndex: index);
    await _playCurrent(restartFromZero: true);
  }

  Future<void> togglePlayPause() async {
    // Primeira reprodução da sessão (ex.: fila restaurada do disco, mas
    // ainda não aberta de verdade no player): carrega a música agora,
    // na posição salva, em vez de simplesmente mandar "play" para um
    // player vazio.
    if (!_engineLoaded) {
      final song = state.currentSong;
      if (song == null) return;
      final lastPositionMs =
          _settings.getInt(AppConstants.keyLastPositionMs, fallback: 0);
      final opened = await _openSong(song, play: true);
      if (!opened) return;
      _engineLoaded = true;
      if (lastPositionMs > 0) {
        await _audio.seek(Duration(milliseconds: lastPositionMs));
      }
      return;
    }
    await _audio.togglePlayPause();
  }

  Future<void> next() => _advance(userInitiated: true);

  Future<void> previous() async {
    if (state.queue.isEmpty) return;

    // Se já tocou mais de 3 segundos, "anterior" volta para o início da
    // música atual (comportamento padrão em players modernos).
    if (_audio.currentPosition > const Duration(seconds: 3)) {
      await _audio.seek(Duration.zero);
      return;
    }

    if (state.hasPrevious) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
      await _playCurrent(restartFromZero: true);
    } else {
      await _audio.seek(Duration.zero);
    }
  }

  Future<void> _advance({required bool userInitiated}) async {
    if (state.queue.isEmpty) return;

    final isLast = state.currentIndex >= state.queue.length - 1;

    if (!isLast) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
      await _playCurrent(restartFromZero: true);
      return;
    }

    // Chegou ao fim da fila.
    if (state.repeatMode == RepeatMode.all) {
      state = state.copyWith(currentIndex: 0);
      await _playCurrent(restartFromZero: true);
    } else if (userInitiated) {
      // Usuário apertou "próxima" no fim da fila sem repetição: volta
      // para o começo, mas pausado.
      state = state.copyWith(currentIndex: 0);
      final opened = await _openSong(state.queue.first, play: false);
      if (opened) _engineLoaded = true;
    } else {
      await _audio.pause();
    }
  }

  Future<void> _playCurrent({required bool restartFromZero}) async {
    final song = state.currentSong;
    if (song == null) return;
    final opened = await _openSong(song, play: true);
    if (opened) _engineLoaded = true;
    _persistQueue();
  }

  /// Ponto único que decide como abrir uma música no player, dependendo
  /// de onde ela vem:
  /// - local: abre o arquivo direto (comportamento de sempre).
  /// - da web já baixada ([Song.localPath] aponta pra um arquivo que
  ///   ainda existe): toca do disco, sem precisar de rede nem resolver
  ///   stream de novo.
  /// - da web ainda não baixada: resolve uma URL de streaming nova bem
  ///   na hora (elas expiram depois de algumas horas, então nunca são
  ///   guardadas nem reaproveitadas) e toca a partir dela.
  ///
  /// Nunca lança: falhas (vídeo removido/indisponível, sem internet
  /// etc.) viram [QueueState.playbackError] em vez de derrubar a
  /// fila/o app. Retorna `true` só quando a reprodução foi de fato
  /// iniciada no [AudioPlayerService].
  Future<bool> _openSong(Song song, {required bool play}) async {
    state = state.copyWith(clearPlaybackError: true);

    if (song.source == SongSource.local) {
      if (!File(song.path).existsSync()) {
        state = state.copyWith(
          playbackError: 'Arquivo não encontrado: "${song.title}".',
        );
        return false;
      }
      await _audio.openAndPlay(song.path, play: play);
      return true;
    }

    // Música da web já baixada: toca do arquivo em disco, se ele ainda
    // existir.
    final cachedPath = song.localPath;
    if (cachedPath != null) {
      if (File(cachedPath).existsSync()) {
        await _audio.openAndPlay(cachedPath, play: play);
        return true;
      }
      // O arquivo baixado sumiu (ex.: apagado manualmente pelo usuário
      // fora do app) — não trava a reprodução por causa disso, só
      // esquece o caminho no banco e cai para resolver o stream normal
      // abaixo, como se a música nunca tivesse sido baixada.
      _library.setLocalPath(song.id, null);
    }

    final remoteId = song.remoteId;
    if (remoteId == null) {
      state = state.copyWith(
        playbackError: 'Música da web sem identificador válido.',
      );
      return false;
    }

    try {
      final youtube = await _ref.read(youtubeClientProvider.future);
      // Diagnóstico temporário (item 5 do sonora-prompt.md: troca de música
      // demorada durante a busca) — mede só o tempo desta chamada
      // específica (processo externo do yt-dlp), pra separar "é a
      // resolução do stream que é lenta" de "é outra coisa". Ver a aba
      // Debug Console do VS Code ao trocar de música. Sem timing para o
      // caminho de erro de propósito: o sintoma relatado é demora até
      // tocar, não uma falha — ver passos 2 e 3 do item 5 antes de mexer
      // em mais alguma coisa aqui. Remover depois de ter a resposta.
      final stopwatch = Stopwatch()..start();
      final stream = await youtube.getAudioStreamUrl(remoteId);
      stopwatch.stop();
      // ignore: avoid_print
      print('Sonora [diagnóstico #5]: getAudioStreamUrl("${song.title}") '
          'levou ${stopwatch.elapsedMilliseconds}ms');
      await _audio.openAndPlayUrl(
        stream.url,
        play: play,
        httpHeaders: stream.httpHeaders,
      );
      return true;
    } on YoutubeRateLimitException catch (e) {
      // ignore: avoid_print
      print('Sonora [YouTube stream]: rate limit ao resolver "${song.title}": $e');
      state = state.copyWith(
        playbackError:
            'O YouTube está limitando temporariamente as requisições feitas '
            'deste computador. Espere alguns minutos antes de tentar tocar '
            'de novo (evite pesquisar/tocar várias músicas seguidas nesse '
            'meio tempo, para não estender o bloqueio).',
      );
      return false;
    } catch (e, stackTrace) {
      // Log temporário, só para diagnosticar o problema relatado — dá pra
      // remover depois que a causa raiz for identificada. Sem isso, o
      // erro real fica invisível: só aparece o aviso genérico na tela.
      // ignore: avoid_print
      print('Sonora [YouTube stream]: falha ao resolver "${song.title}" '
          '(remoteId=$remoteId): $e\n$stackTrace');
      state = state.copyWith(
        playbackError:
            'Não foi possível reproduzir "${song.title}" agora — o vídeo '
            'pode ter sido removido, ficado indisponível, ou faltou conexão.',
      );
      return false;
    }
  }

  /// Reflete, na fila em memória, um download concluído em outro lugar
  /// (ver `LibraryNotifier`/`DownloadNotifier`) — mesma lógica de
  /// [updateSongFavorite], e pelo mesmo motivo: a fila guarda sua
  /// própria cópia dos `Song`, então uma mudança só no banco não
  /// apareceria aqui sozinha.
  void updateSongLocalPath(int songId, String? localPath) {
    List<Song> patch(List<Song> songs) => [
          for (final s in songs)
            if (s.id == songId)
              s.copyWith(localPath: localPath, clearLocalPath: localPath == null)
            else
              s,
        ];
    state = state.copyWith(
      queue: patch(state.queue),
      originalOrder: patch(state.originalOrder),
    );
  }

  Future<void> toggleShuffle() async {
    final enable = !state.shuffleEnabled;
    _settings.setBool(AppConstants.keyShuffleEnabled, enable);

    if (state.queue.isEmpty) {
      state = state.copyWith(shuffleEnabled: enable);
      return;
    }

    final current = state.currentSong;
    if (enable) {
      final shuffled = ShuffleUtils.shuffle(state.originalOrder, keepFirst: current);
      state = state.copyWith(
        shuffleEnabled: true,
        queue: shuffled,
        currentIndex: current != null ? shuffled.indexOf(current) : 0,
      );
    } else {
      final restored = state.originalOrder;
      state = state.copyWith(
        shuffleEnabled: false,
        queue: restored,
        currentIndex: current != null ? restored.indexOf(current) : 0,
      );
    }
    _persistQueue();
  }

  void cycleRepeatMode() {
    final next = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeatMode: next);
    _settings.setString(AppConstants.keyRepeatMode, next.name);
  }

  void savePlaybackPosition(Duration position) {
    _settings.setInt(AppConstants.keyLastPositionMs, position.inMilliseconds);
  }

  void _persistQueue() {
    _settings.setIntList(
      AppConstants.keyLastQueue,
      state.queue.map((s) => s.id).toList(),
    );
    _settings.setInt(AppConstants.keyLastQueueIndex, state.currentIndex);
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    super.dispose();
  }
}
