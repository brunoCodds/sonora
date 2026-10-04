import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../constants/app_constants.dart';

/// Tamanho e posição "normais" (modo cheio) salvos pelo
/// [WindowBoundsPersistence] na última vez que o usuário redimensionou
/// ou moveu a janela.
///
/// [position] é `null` quando ainda não há nada salvo (primeira execução)
/// ou quando o valor salvo é suspeito demais pra confiar (ver
/// [loadSavedWindowBounds]) — nesses casos quem for usar isto deve
/// centralizar a janela em vez de posicionar num ponto específico.
class SavedWindowBounds {
  final Size size;
  final Offset? position;
  const SavedWindowBounds({required this.size, required this.position});
}

/// Lê uma posição de janela salva sob o par de chaves [xKey]/[yKey],
/// devolvendo `null` quando não há nada salvo ainda ou quando o valor é
/// absurdo demais pra confiar (ex.: de um monitor secundário que não
/// está mais conectado) — nesse caso é melhor centralizar do que
/// arriscar abrir fora da tela. Compartilhado entre a posição da janela
/// em modo cheio e a posição do painel mini/bandeja (ver
/// `TrayModeController`), que usam pares de chaves diferentes mas a
/// mesma lógica de validação.
Offset? loadSavedPosition(
  SettingsRepository settings, {
  required String xKey,
  required String yKey,
}) {
  final rawX = settings.getDouble(xKey, fallback: double.nan);
  final rawY = settings.getDouble(yKey, fallback: double.nan);

  const positionSanityBound = 10000.0;
  final isValid = !rawX.isNaN &&
      !rawY.isNaN &&
      rawX > -positionSanityBound &&
      rawX < positionSanityBound &&
      rawY > -positionSanityBound &&
      rawY < positionSanityBound;

  return isValid ? Offset(rawX, rawY) : null;
}

/// Lê do banco (via [SettingsRepository]) o tamanho/posição salvos da
/// janela em modo cheio. Usado tanto na abertura do app (`main.dart`)
/// quanto ao voltar do modo mini/bandeja pro modo cheio
/// (`TrayModeController`) — os dois precisam do mesmo resultado, daí
/// esse helper em vez de duas cópias da mesma lógica.
SavedWindowBounds loadSavedWindowBounds(SettingsRepository settings) {
  final savedWidth = settings.getDouble(
    AppConstants.keyWindowWidth,
    fallback: AppConstants.defaultWindowWidth,
  );
  final savedHeight = settings.getDouble(
    AppConstants.keyWindowHeight,
    fallback: AppConstants.defaultWindowHeight,
  );

  return SavedWindowBounds(
    // math.max (não .clamp): .clamp devolve `num`, não `double`, o que
    // quebraria a atribuição a `Size` (que exige `double`) em tempo de
    // compilação — pegadinha clássica do Dart.
    size: Size(
      math.max(savedWidth, AppConstants.minWindowWidth),
      math.max(savedHeight, AppConstants.minWindowHeight),
    ),
    position: loadSavedPosition(
      settings,
      xKey: AppConstants.keyWindowPosX,
      yKey: AppConstants.keyWindowPosY,
    ),
  );
}
