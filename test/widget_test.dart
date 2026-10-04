// Teste básico de smoke test: garante apenas que o app sobe sem travar.
//
// O Sonora abre um banco de dados real e a janela desktop no main(), então
// aqui testamos só a construção da árvore de widgets raiz (SonoraApp),
// sem depender de banco de dados ou plugins nativos.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonora/app.dart';
import 'package:sonora/data/database/app_database.dart';
import 'package:sonora/providers/database_provider.dart';

void main() {
  testWidgets('Sonora abre sem erros', (WidgetTester tester) async {
    final database = await AppDatabase.open();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const SonoraApp(),
      ),
    );

    // A tela inicial (Biblioteca) deve aparecer.
    expect(find.text('Biblioteca'), findsWidgets);
  });
}
