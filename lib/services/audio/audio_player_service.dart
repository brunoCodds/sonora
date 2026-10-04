import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// Encapsula o motor de reprodução (media_kit/libmpv).
///
/// IMPORTANTE — histórico: esta classe já teve uma versão que rodava o
/// [Player] inteiro numa Isolate Dart separada, na tentativa de isolar as
/// threads nativas do libmpv da isolate principal (a que desenha a UI e
/// processa o loop de redimensionamento do Windows). Essa tentativa foi
/// revertida porque:
///
/// 1. `MediaKit.ensureInitialized()` chamado de dentro de uma isolate
///    secundária derrubava a isolate com
///    `FormatException: Invalid number (at character 1)` dentro de
///    `NativeReferenceHolder._ensureInitialized` — esse mecanismo interno
///    do media_kit não foi desenhado para inicializar fora da isolate
///    raiz. Como a exceção não tratada mata a isolate silenciosamente
///    (sem propagar pro lado principal), o app ficava com a música nunca
///    tocando — o comando `open`/`play` ficava pendurado para sempre
///    esperando um `commandPort` que nunca chegava.
/// 2. Mesmo se a inicialização funcionasse, os logs de crash mostravam o
///    mesmo access violation acontecendo, então a mudança não resolvia o
///    problema original — só trocava um bug por outro.
///
/// A causa mais provável do crash de resize (ver `resize_playback_guard`
/// e `PlayerProgressBar`) é outra: um bug conhecido e ainda em aberto do
/// próprio motor do Flutter no Windows, em que widgets com semântica
/// (accessibility) que reconstroem com muita frequência — como o
/// `Slider` da barra de progresso, atualizado a cada evento de posição
/// do player — em conjunto com o recálculo de layout/semântica disparado
/// pelo redimensionamento, corrompem a árvore de acessibilidade nativa
/// (`ui::AXTree`) e derrubam o processo. Isso explica por que o crash só
/// acontece redimensionando **com música tocando** (é o que mantém a
/// barra de progresso se reconstruindo o tempo todo) e por que a tela de
/// biblioteca (grade grande = árvore de semântica maior) piorava a
/// frequência. Ver `progress_bar.dart` para a mitigação.
class AudioPlayerService {
  final Player _player = Player();

  /// Emite a posição de reprodução por polling (a cada 250ms, só enquanto
  /// `playing` é verdadeiro) em vez de repassar direto o stream nativo
  /// `_player.stream.position`.
  ///
  /// Isso substitui uma tentativa anterior que filtrava
  /// `_player.stream.position` com `.where()` no lado do provider
  /// (audio_providers.dart) para conseguir o mesmo efeito de amostragem.
  /// Na prática a barra de progresso parou de andar — o stream nativo de
  /// posição nem sempre dispara com uma frequência confiável nesse
  /// ambiente (varia por build do media_kit/libmpv), e depender só dele
  /// deixou a UI sem nenhuma atualização. Gerar a posição por polling
  /// aqui, direto de `_player.state.position` (o valor "atual" que o
  /// media_kit sempre mantém atualizado internamente, mesmo se o stream
  /// de eventos falhar), é uma fonte muito mais previsível — não depende
  /// de quantos eventos nativos chegam nem da frequência deles.
  final _positionController = StreamController<Duration>.broadcast();
  Timer? _positionTimer;

  AudioPlayerService() {
    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_positionController.hasListener) return;
      _positionController.add(_player.state.position);
    });
    // Também repassa o stream nativo, para o caso de ele emitir eventos
    // mais cedo que o timer (ex.: logo após um seek) — o polling acima
    // garante que a UI nunca fica travada, e isto aqui só ajuda a deixar
    // as coisas um pouco mais responsivas quando o evento nativo chega.
    _player.stream.position.listen((p) {
      if (!_positionController.hasListener) return;
      _positionController.add(p);
    });
  }

  Stream<Duration> get position => _positionController.stream;
  Stream<Duration> get duration => _player.stream.duration;
  Stream<bool> get playing => _player.stream.playing;
  Stream<bool> get completed => _player.stream.completed;
  Stream<double> get volume => _player.stream.volume;
  Stream<bool> get buffering => _player.stream.buffering;

  Duration get currentPosition => _player.state.position;
  Duration get currentDuration => _player.state.duration;
  bool get isPlaying => _player.state.playing;
  double get currentVolume => _player.state.volume;

  Future<void> openAndPlay(String filePath, {bool play = true}) async {
    final uri = Uri.file(File(filePath).absolute.path).toString();
    await _player.open(Media(uri), play: play);
  }

  /// Igual a [openAndPlay], mas para uma URL de rede já pronta para tocar
  /// (ex.: um stream de áudio do YouTube resolvido por
  /// `YoutubeClient.getAudioStreamUrl`) — o media_kit aceita `Media(url)`
  /// com http(s) nativamente, então não precisa do `Uri.file(...)` que
  /// [openAndPlay] usa para caminhos locais.
  ///
  /// [httpHeaders], quando informado, acompanha a URL em toda requisição
  /// que o media_kit/libmpv fizer pra ela — necessário porque a URL
  /// resolvida pelo yt-dlp (`googlevideo.com/videoplayback?...`) às vezes
  /// só funciona se quem for buscá-la mandar o mesmo `User-Agent` que o
  /// yt-dlp usou pra resolvê-la (ver `YoutubeClient.getAudioStreamUrl`).
  ///
  /// Quem chama isto é responsável por resolver a URL "na hora": URLs de
  /// streaming do YouTube expiram depois de algumas horas, então nunca
  /// devem ser guardadas (no banco, em `Song.path`, etc.) — só usadas
  /// uma vez, aqui.
  Future<void> openAndPlayUrl(
    String url, {
    bool play = true,
    Map<String, String>? httpHeaders,
  }) async {
    await _player.open(Media(url, httpHeaders: httpHeaders), play: play);
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> seekRelative(Duration offset) {
    final target = currentPosition + offset;
    final clamped = target.isNegative ? Duration.zero : target;
    return seek(clamped);
  }

  /// Volume no intervalo de 0 a 100 (padrão do media_kit).
  Future<void> setVolume(double volume) {
    final clamped = volume.clamp(0.0, 100.0);
    return _player.setVolume(clamped);
  }

  Future<void> stop() => _player.stop();

  /// Suspende a reprodução por causa de um redimensionamento de janela em
  /// andamento. Hoje equivale a [pause]. Fica como método próprio (em vez
  /// de quem chama usar `pause()`/`play()` diretamente) para que, se
  /// pausar sozinho não for suficiente em algum ambiente, dê para trocar
  /// de estratégia em um único lugar, sem precisar mexer no código que
  /// reage ao redimensionamento.
  Future<void> suspendForResize() => pause();

  /// Contraparte de [suspendForResize]: retoma a reprodução depois que o
  /// redimensionamento termina.
  Future<void> resumeFromResize() => play();

  void dispose() {
    _positionTimer?.cancel();
    _positionController.close();
    _player.dispose();
  }
}
