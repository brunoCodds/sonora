import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';

/// A instância real é criada de forma assíncrona em `main()` (antes de
/// `runApp`) e injetada via `ProviderScope(overrides: [...])`. Isso evita
/// telas de carregamento no meio da árvore de widgets só para abrir o
/// banco de dados.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider deve ser sobrescrito em main() com a instância real.',
  );
});
