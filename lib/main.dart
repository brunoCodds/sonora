import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/window_bounds.dart';
import 'core/utils/window_glass.dart';
import 'data/database/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'providers/database_provider.dart';
import 'services/youtube/ytdlp_process.dart';

/// Mude para `true` SÓ enquanto estiver investigando um problema de
/// verdade com busca/streaming/download do YouTube (ex.: um bloqueio de
/// tráfego). Isso liga um log bem detalhado (o comando yt-dlp completo e a
/// saída crua dele) que aparece no console/terminal ao rodar o app. Volte
/// para `false` depois — não é pra ficar ligado no dia a dia, e o log pode
/// conter a URL de streaming resolvida e os headers HTTP associados a
/// ela, então não cole a saída em lugares públicos sem revisar antes.
const kEnableYoutubeVerboseLogging = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kEnableYoutubeVerboseLogging) {
    YtDlpProcess.verboseLoggingEnabled = true;
  }

  // Inicializa o motor de reprodução de áudio (media_kit/libmpv).
  MediaKit.ensureInitialized();

  // Abre (criando se necessário) o banco de dados local antes de
  // desenhar qualquer tela, evitando telas de carregamento no meio da
  // árvore de widgets. Precisa vir antes da configuração da janela
  // porque também usamos ele pra ler o tamanho/posição salvos abaixo.
  final database = await AppDatabase.open();
  final settings = SettingsRepository(database);

  // Restaura o tamanho e a posição salvos da janela (ver
  // `WindowBoundsPersistence`, que grava esses valores a cada
  // redimensionamento/movimento). Se não houver nada salvo ainda
  // (primeira execução), cai nos valores padrão e centraliza.
  final savedBounds = loadSavedWindowBounds(settings);

  // Prepara o efeito de vidro do painel "Discreto" (ver WindowGlass). Precisa
  // vir antes do runApp; não aplica efeito nenhum agora, só inicializa, e
  // nunca lança exceção (se falhar, o painel só fica sem vidro).
  await WindowGlass.init();

  // Configura a janela desktop (tamanho, mínimo, título).
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    size: savedBounds.size,
    minimumSize: const Size(AppConstants.minWindowWidth, AppConstants.minWindowHeight),
    center: savedBounds.position == null,
    title: AppConstants.appName,
    backgroundColor: Colors.transparent,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    final position = savedBounds.position;
    if (position != null) {
      // Posiciona enquanto a janela ainda está oculta, para não haver
      // nenhum "pulo" visível antes de show().
      await windowManager.setPosition(position);
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
      ],
      child: const SonoraApp(),
    ),
  );
}
