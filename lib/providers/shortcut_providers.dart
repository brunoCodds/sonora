import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/settings_repository.dart';
import '../shortcuts/key_binding.dart';
import '../shortcuts/shortcut_action.dart';
import 'repository_providers.dart';

/// Combinação de cada [ShortcutAction] com sua tecla padrão de fábrica —
/// o mesmo esquema que já existia antes de os atalhos serem
/// personalizáveis. `null` significa "sem atalho".
const Map<ShortcutAction, KeyBinding?> kDefaultShortcutBindings = {
  ShortcutAction.playPause: KeyBinding(LogicalKeyboardKey.space),
  ShortcutAction.next: KeyBinding(LogicalKeyboardKey.arrowRight, ctrl: true),
  ShortcutAction.previous: KeyBinding(LogicalKeyboardKey.arrowLeft, ctrl: true),
  ShortcutAction.seekForward: KeyBinding(LogicalKeyboardKey.arrowRight),
  ShortcutAction.seekBackward: KeyBinding(LogicalKeyboardKey.arrowLeft),
  ShortcutAction.volumeUp: KeyBinding(LogicalKeyboardKey.arrowUp),
  ShortcutAction.volumeDown: KeyBinding(LogicalKeyboardKey.arrowDown),
  ShortcutAction.mute: KeyBinding(LogicalKeyboardKey.keyM),
};

/// Por que o motivo da rebinding poder falhar é mostrado na UI (conflito
/// com outro atalho já existente), o resultado é modelado explicitamente
/// em vez de um simples bool.
class RebindResult {
  final bool success;
  final ShortcutAction? conflictsWith;
  const RebindResult.success() : success = true, conflictsWith = null;
  const RebindResult.conflict(ShortcutAction other) : success = false, conflictsWith = other;
}

class ShortcutBindingsController extends StateNotifier<Map<ShortcutAction, KeyBinding?>> {
  final SettingsRepository _settings;

  ShortcutBindingsController(this._settings) : super(_load(_settings));

  static Map<ShortcutAction, KeyBinding?> _load(SettingsRepository settings) {
    final raw = settings.getString(AppConstants.keyShortcutBindings);
    if (raw == null || raw.isEmpty) return Map.of(kDefaultShortcutBindings);

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = Map<ShortcutAction, KeyBinding?>.of(kDefaultShortcutBindings);
      for (final action in ShortcutAction.values) {
        final storedValue = decoded[action.name] as String?;
        if (storedValue == null) continue;
        // String vazia representa "sem atalho" (usuário removeu de
        // propósito) — precisa ser distinguido de "não salvo ainda"
        // (que cai no padrão de fábrica, tratado acima).
        result[action] = storedValue.isEmpty ? null : KeyBinding.fromStorageString(storedValue);
      }
      return result;
    } catch (_) {
      // Configuração corrompida/de uma versão futura incompatível: não
      // trava o app, só volta pro padrão.
      return Map.of(kDefaultShortcutBindings);
    }
  }

  void _persist() {
    final map = <String, String>{
      for (final entry in state.entries) entry.key.name: entry.value?.toStorageString() ?? '',
    };
    _settings.setString(AppConstants.keyShortcutBindings, jsonEncode(map));
  }

  /// Tenta atribuir [binding] a [action]. Recusa se a mesma combinação já
  /// estiver em uso por outra ação — o chamador decide o que mostrar ao
  /// usuário a partir do [RebindResult] devolvido, em vez de sobrescrever
  /// silenciosamente.
  RebindResult rebind(ShortcutAction action, KeyBinding binding) {
    for (final entry in state.entries) {
      if (entry.key != action && entry.value == binding) {
        return RebindResult.conflict(entry.key);
      }
    }
    state = {...state, action: binding};
    _persist();
    return const RebindResult.success();
  }

  /// Remove o atalho de [action] (fica sem tecla nenhuma).
  void clear(ShortcutAction action) {
    state = {...state, action: null};
    _persist();
  }

  void resetAction(ShortcutAction action) {
    state = {...state, action: kDefaultShortcutBindings[action]};
    _persist();
  }

  void resetAll() {
    state = Map.of(kDefaultShortcutBindings);
    _persist();
  }
}

final shortcutBindingsProvider =
    StateNotifierProvider<ShortcutBindingsController, Map<ShortcutAction, KeyBinding?>>((ref) {
  return ShortcutBindingsController(ref.watch(settingsRepositoryProvider));
});
