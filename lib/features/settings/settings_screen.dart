import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/supported_formats.dart';
import '../../core/theme/app_palette.dart';
import '../../providers/library_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/service_providers.dart';
import '../../services/youtube/youtube_download_service.dart';
import 'widgets/shortcut_bindings_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late List<String> _folders;

  /// Pasta de downloads escolhida pelo usuário; `null` = usa a padrão.
  String? _customDownloadFolder;

  /// Pasta padrão dos downloads (só pra mostrar na tela enquanto o usuário
  /// não escolheu outra). Vem de forma assíncrona — ver
  /// [_loadDefaultDownloadFolder].
  String _defaultDownloadFolder = '';

  @override
  void initState() {
    super.initState();
    _folders = ref.read(settingsRepositoryProvider).getStringList(AppConstants.keyImportFolders);
    _customDownloadFolder =
        ref.read(settingsRepositoryProvider).getString(AppConstants.keyDownloadFolder);
    _loadDefaultDownloadFolder();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _refreshFolders() {
    setState(() {
      _folders =
          ref.read(settingsRepositoryProvider).getStringList(AppConstants.keyImportFolders);
    });
  }

  Future<void> _loadDefaultDownloadFolder() async {
    final path = await YoutubeDownloadService.defaultDownloadsPath();
    if (!mounted) return;
    setState(() => _defaultDownloadFolder = path);
  }

  Future<void> _chooseDownloadFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecionar pasta para as músicas baixadas',
    );
    if (folder == null) return; // usuário cancelou.

    ref.read(settingsRepositoryProvider).setString(AppConstants.keyDownloadFolder, folder);
    if (!mounted) return;
    setState(() => _customDownloadFolder = folder);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pasta de downloads atualizada')),
    );
  }

  void _resetDownloadFolder() {
    ref.read(settingsRepositoryProvider).remove(AppConstants.keyDownloadFolder);
    setState(() => _customDownloadFolder = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final songCount = ref.watch(libraryNotifierProvider).songs.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Text('Configurações', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        _Section(
          title: 'Pastas importadas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Nenhuma pasta importada ainda.',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                )
              else
                for (final folder in _folders)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.folder_rounded, size: 18, color: palette.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(folder, overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => _removeFolder(folder),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(libraryNotifierProvider.notifier).importFolder();
                      _refreshFolders();
                    },
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: const Text('Adicionar pasta'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(libraryNotifierProvider.notifier).rescanImportedFolders(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Buscar novas músicas'),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Section(
          title: 'Biblioteca',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$songCount música${songCount == 1 ? '' : 's'} na biblioteca',
                  style: TextStyle(color: palette.textSecondary)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(libraryNotifierProvider.notifier).pruneMissingFiles();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Arquivos ausentes removidos da biblioteca')),
                  );
                },
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Remover arquivos que não existem mais'),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Downloads da web',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pasta onde as músicas da web são salvas quando você clica em '
                'instalar. A mudança vale só para os próximos downloads — '
                'músicas já instaladas continuam onde estão.',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.folder_rounded, size: 18, color: palette.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _customDownloadFolder ?? _defaultDownloadFolder,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              if (_customDownloadFolder == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 28),
                  child: Text(
                    'Pasta padrão',
                    style: TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _chooseDownloadFolder,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Escolher pasta'),
                  ),
                  if (_customDownloadFolder != null)
                    OutlinedButton.icon(
                      onPressed: _resetDownloadFolder,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Restaurar padrão'),
                    ),
                ],
              ),
            ],
          ),
        ),
        _Section(
          title: 'Formatos suportados',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SupportedFormats.audioExtensions
                .map((ext) => Chip(
                      label: Text('.$ext'),
                      backgroundColor: palette.surfaceHighlight,
                      side: BorderSide.none,
                    ))
                .toList(),
          ),
        ),
        _Section(
          title: 'Reprodução da web',
          child: Consumer(
            builder: (context, ref, _) {
              final youtubeClientAsync = ref.watch(youtubeClientProvider);

              return youtubeClientAsync.when(
                data: (_) => Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: palette.accent),
                    const SizedBox(width: 8),
                    const Text('Pronto — busca e streaming da web funcionando.'),
                  ],
                ),
                loading: () => Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Preparando reprodução da web...',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
                error: (error, _) => Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: palette.error),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Falha ao preparar a reprodução da web.'),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(youtubeClientProvider),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const _Section(
          title: 'Atalhos de teclado',
          child: ShortcutBindingsEditor(),
        ),
        _Section(
          title: 'Sobre',
          child: Text(
            '${AppConstants.appName} é um player de música que organiza e reproduz sua '
            'própria biblioteca local, e também busca, importa playlists e toca música '
            'direto da web.',
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
      ],
    );
  }

  void _removeFolder(String folder) {
    final repo = ref.read(settingsRepositoryProvider);
    final updated = List<String>.from(_folders)..remove(folder);
    repo.setStringList(AppConstants.keyImportFolders, updated);
    _refreshFolders();
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

