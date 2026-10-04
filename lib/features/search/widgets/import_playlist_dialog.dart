import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/playlist_providers.dart';
import '../../../providers/service_providers.dart';
import '../../../services/web_music/playlist_import_service.dart';

void showImportPlaylistDialog(BuildContext context, WidgetRef ref, {String? initialLink}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ImportPlaylistDialog(initialLink: initialLink),
  );
}

enum _ImportStep { input, importing, done, error }

class _ImportPlaylistDialog extends ConsumerStatefulWidget {
  final String? initialLink;
  const _ImportPlaylistDialog({this.initialLink});

  @override
  ConsumerState<_ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends ConsumerState<_ImportPlaylistDialog> {
  late final _linkController = TextEditingController(text: widget.initialLink ?? '');
  final _nameController = TextEditingController();

  _ImportStep _step = _ImportStep.input;
  int _done = 0;
  int _total = 0;
  String? _errorMessage;
  PlaylistImportResult? _result;

  @override
  void dispose() {
    _linkController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surfaceVariant,
      title: const Text('Importar playlist'),
      content: SizedBox(width: 380, child: _buildContent()),
      actions: _buildActions(),
    );
  }

  Widget _buildContent() {
    final palette = context.palette;
    switch (_step) {
      case _ImportStep.input:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cole o link de uma playlist pública do YouTube.',
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _linkController,
              autofocus: true,
              // O botão "Importar" (em _buildActions) só habilita se este
              // campo tiver texto. Sem este rebuild, o botão ficava preso
              // no estado de quando o diálogo abriu (vazio => desabilitado),
              // porque nada mandava o diálogo se redesenhar ao digitar ou
              // colar. Só funcionava com [initialLink], que já abre o campo
              // preenchido.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Link da playlist'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Nome da playlist (opcional — usamos o da fonte se deixar em branco)',
              ),
            ),
          ],
        );
      case _ImportStep.importing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _total > 0
                  ? 'Buscando faixas correspondentes no YouTube... $_done de $_total'
                  : 'Lendo a playlist...',
              style: TextStyle(color: palette.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case _ImportStep.done:
        final result = _result!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${result.matched.length} música(s) importada(s).'),
            if (result.notFoundTitles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${result.notFoundTitles.length} não encontrada(s) no YouTube:',
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final title in result.notFoundTitles)
                      Text(
                        '• $title',
                        style: TextStyle(fontSize: 12, color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      case _ImportStep.error:
        return Text(
          _errorMessage ?? 'Não foi possível importar essa playlist.',
          style: TextStyle(color: palette.textSecondary),
        );
    }
  }

  List<Widget> _buildActions() {
    switch (_step) {
      case _ImportStep.input:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _linkController.text.trim().isEmpty ? null : _startImport,
            child: const Text('Importar'),
          ),
        ];
      case _ImportStep.importing:
        return const [];
      case _ImportStep.done:
      case _ImportStep.error:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Concluir'),
          ),
        ];
    }
  }

  Future<void> _startImport() async {
    final link = _linkController.text.trim();
    setState(() {
      _step = _ImportStep.importing;
      _done = 0;
      _total = 0;
    });

    try {
      final service = await ref.read(playlistImportServiceProvider.future);
      final result = await service.importFromLink(
        link,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );

      if (result.matched.isEmpty) {
        setState(() {
          _step = _ImportStep.error;
          _errorMessage = 'Nenhuma música dessa playlist pôde ser encontrada no YouTube.';
        });
        return;
      }

      final chosenName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : (result.playlistName ?? 'Playlist importada');

      final libraryNotifier = ref.read(libraryNotifierProvider.notifier);
      final songs = result.matched.map(libraryNotifier.materializeWebSong).toList();

      final playlistsNotifier = ref.read(playlistsNotifierProvider.notifier);
      final playlist = playlistsNotifier.create(chosenName);
      playlistsNotifier.addSongs(playlist.id, songs.map((s) => s.id));

      if (!mounted) return;
      setState(() {
        _step = _ImportStep.done;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _ImportStep.error;
        _errorMessage = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
      });
    }
  }
}
