import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio/audio_player_service.dart';
import '../services/audio/queue_controller.dart';
import 'repository_providers.dart';

/// Instância única do serviço de reprodução, viva por toda a sessão do
/// app (`keepAlive`), já que a música deve continuar tocando enquanto o
/// usuário navega entre telas.
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(service.dispose);
  return service;
}, name: 'audioPlayerServiceProvider');

final queueControllerProvider =
    StateNotifierProvider<QueueController, QueueState>((ref) {
  return QueueController(
    ref.watch(audioPlayerServiceProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(libraryRepositoryProvider),
    ref,
  );
});

/// Posição de reprodução.
///
/// A amostragem (~4x/segundo) já acontece dentro do [AudioPlayerService]
/// via polling, então este provider só repassa o stream — ver o
/// comentário em `AudioPlayerService._positionTimer` para o porquê da
/// mudança (o filtro que existia aqui antes, em cima do stream nativo do
/// media_kit, deixou a barra de progresso travada em 0:00 nalguns
/// ambientes).
final playerPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioPlayerServiceProvider).position;
});

final playerDurationProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioPlayerServiceProvider).duration;
});

final playerPlayingProvider = StreamProvider<bool>((ref) {
  return ref.watch(audioPlayerServiceProvider).playing;
});

final playerBufferingProvider = StreamProvider<bool>((ref) {
  return ref.watch(audioPlayerServiceProvider).buffering;
});

final playerVolumeProvider = StreamProvider<double>((ref) {
  return ref.watch(audioPlayerServiceProvider).volume;
});
