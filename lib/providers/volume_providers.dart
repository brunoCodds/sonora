import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/settings_repository.dart';
import '../services/audio/audio_player_service.dart';
import 'audio_providers.dart';
import 'repository_providers.dart';

class VolumeState {
  /// Volume desejado pelo usuário (0-100), preservado mesmo com mudo
  /// ativado, para poder restaurá-lo depois.
  final double volume;
  final bool muted;

  const VolumeState({this.volume = 100, this.muted = false});

  double get effectiveVolume => muted ? 0 : volume;

  VolumeState copyWith({double? volume, bool? muted}) {
    return VolumeState(
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }
}

class VolumeController extends StateNotifier<VolumeState> {
  final AudioPlayerService _audio;
  final SettingsRepository _settings;

  VolumeController(this._audio, this._settings)
      : super(
          VolumeState(
            volume: _settings.getDouble(AppConstants.keyVolume, fallback: 100),
            muted: _settings.getBool(AppConstants.keyMuted),
          ),
        ) {
    _audio.setVolume(state.effectiveVolume);
  }

  void setVolume(double value) {
    final clamped = value.clamp(0.0, 100.0);
    final unmute = clamped > 0 && state.muted;
    state = state.copyWith(volume: clamped, muted: unmute ? false : null);
    _settings.setDouble(AppConstants.keyVolume, clamped);
    if (unmute) _settings.setBool(AppConstants.keyMuted, false);
    _audio.setVolume(state.effectiveVolume);
  }

  void toggleMute() {
    final muted = !state.muted;
    state = state.copyWith(muted: muted);
    _settings.setBool(AppConstants.keyMuted, muted);
    _audio.setVolume(state.effectiveVolume);
  }

  void nudge(double delta) => setVolume(state.volume + delta);
}

final volumeControllerProvider =
    StateNotifierProvider<VolumeController, VolumeState>((ref) {
  return VolumeController(
    ref.watch(audioPlayerServiceProvider),
    ref.watch(settingsRepositoryProvider),
  );
});
