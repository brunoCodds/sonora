import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/database/app_database.dart';
import '../data/models/song.dart';
import '../data/models/song_source.dart';
import '../data/models/sort_field.dart';
import '../data/models/youtube_search_result.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../services/file_import/file_import_service.dart';
import '../services/metadata/metadata_service.dart';
import 'audio_providers.dart';
import 'database_provider.dart';
import 'favorites_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';

class LibraryState {
  final List<Song> songs;
  final bool isLoading;
  final bool isImporting;
  final int importCurrent;
  final int importTotal;
  final String searchQuery;
  final SortField sortField;
  final bool sortAscending;
  final String? errorMessage;

  const LibraryState({
    this.songs = const [],
    this.isLoading = true,
    this.isImporting = false,
    this.importCurrent = 0,
    this.importTotal = 0,
    this.searchQuery = '',
    this.sortField = SortField.title,
    this.sortAscending = true,
    this.errorMessage,
  });

  List<Song> get filteredSortedSongs {
    Iterable<Song> result = songs;

    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((s) =>
          s.title.toLowerCase().contains(query) ||
          s.artist.toLowerCase().contains(query) ||
          s.album.toLowerCase().contains(query));
    }

    final list = result.toList();
    list.sort((a, b) {
      int cmp;
      switch (sortField) {
        case SortField.title:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case SortField.artist:
          cmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case SortField.album:
          cmp = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          break;
        case SortField.year:
          cmp = (a.year ?? 0).compareTo(b.year ?? 0);
          break;
        case SortField.dateAdded:
          cmp = a.dateAdded.compareTo(b.dateAdded);
          break;
        case SortField.duration:
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });
    return list;
  }

  LibraryState copyWith({
    List<Song>? songs,
    bool? isLoading,
    bool? isImporting,
    int? importCurrent,
    int? importTotal,
    String? searchQuery,
    SortField? sortField,
    bool? sortAscending,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      songs: songs ?? this.songs,
      isLoading: isLoading ?? this.isLoading,
      isImporting: isImporting ?? this.isImporting,
      importCurrent: importCurrent ?? this.importCurrent,
      importTotal: importTotal ?? this.importTotal,
      searchQuery: searchQuery ?? this.searchQuery,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final LibraryRepository _repository;
  final MetadataService _metadata;
  final FileImportService _fileImport;
  final SettingsRepository _settings;
  final AppDatabase _database;
  final Ref _ref;

  LibraryNotifier(
    this._repository,
    this._metadata,
    this._fileImport,
    this._settings,
    this._database,
    this._ref,
  ) : super(
          LibraryState(
            sortField:
                SortField.fromName(_settings.getString(AppConstants.keySortField)),
            sortAscending:
                _settings.getBool(AppConstants.keySortAscending, fallback: true),
          ),
        ) {
    loadFromDb();
  }

  void loadFromDb() {
    state = state.copyWith(songs: _repository.getAllSongs(), isLoading: false);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSort(SortField field) {
    final ascending =
        field == state.sortField ? !state.sortAscending : true;
    state = state.copyWith(sortField: field, sortAscending: ascending);
    _settings.setString(AppConstants.keySortField, field.name);
    _settings.setBool(AppConstants.keySortAscending, ascending);
  }

  Future<void> importFiles() async {
    final paths = await _fileImport.pickAudioFiles();
    if (paths.isEmpty) return;
    await _importPaths(paths, skipExisting: false);
  }

  Future<void> importFolder() async {
    final folder = await _fileImport.pickFolder();
    if (folder == null) return;

    final folders = _settings.getStringList(AppConstants.keyImportFolders);
    if (!folders.contains(folder)) {
      folders.add(folder);
      _settings.setStringList(AppConstants.keyImportFolders, folders);
    }

    final paths = _fileImport.scanFolder(folder);
    await _importPaths(paths, skipExisting: true);
  }

  /// Reprocessa todas as pastas já importadas anteriormente, adicionando
  /// arquivos novos encontrados nelas.
  Future<void> rescanImportedFolders() async {
    final folders = _settings.getStringList(AppConstants.keyImportFolders);
    if (folders.isEmpty) return;
    final paths = _fileImport.scanFolders(folders);
    await _importPaths(paths, skipExisting: true);
  }

  Future<void> _importPaths(
    List<String> paths, {
    required bool skipExisting,
  }) async {
    final toProcess = skipExisting
        ? paths.where((p) => !_repository.existsByPath(p)).toList()
        : paths;

    if (toProcess.isEmpty) return;

    state = state.copyWith(
      isImporting: true,
      importCurrent: 0,
      importTotal: toProcess.length,
      clearError: true,
    );

    final coversDir = await _database.coversDirectory();

    for (var i = 0; i < toProcess.length; i++) {
      try {
        final track = await _metadata.readTrack(toProcess[i], coversDir);
        _repository.upsertSong(track.toSong());
      } catch (_) {
        // Ignora arquivos individuais que falharem ao ler metadados,
        // sem interromper o restante da importação.
      }
      state = state.copyWith(importCurrent: i + 1);
    }

    state = state.copyWith(isImporting: false);
    loadFromDb();
  }

  void removeSong(int id) {
    _repository.deleteSong(id);
    loadFromDb();
  }

  void removeSongs(Iterable<int> ids) {
    _repository.deleteSongs(ids);
    loadFromDb();
  }

  /// Limpa da biblioteca o que aponta pra arquivo que não existe mais em
  /// disco: músicas locais são removidas; músicas da web instaladas só
  /// deixam de constar como baixadas (ver `LibraryRepository.pruneMissingFiles`).
  void pruneMissingFiles() {
    _repository.pruneMissingFiles((path) => File(path).existsSync());
    loadFromDb();
    // Uma música da web pode ter perdido o download sem ter sido removida,
    // então a lista de favoritos (que também mostra músicas da web) precisa
    // reler o banco.
    _ref.read(favoritesNotifierProvider.notifier).loadFromDb();
  }

  /// Alterna favorito e persiste no banco. Funciona tanto para músicas
  /// locais quanto da web — a coluna `is_favorite` é a mesma para as
  /// duas (ver decisão de unificar o modelo de dados). Atualiza:
  /// - `state.songs`, quando a música está na Biblioteca (uma música
  ///   local sempre está; uma da web só se já foi instalada — ver
  ///   `LibraryRepository.getAllSongs`);
  /// - a fila de reprodução atual (`queueControllerProvider`), já que
  ///   ela guarda sua própria cópia do `Song`;
  /// - `favoritesNotifierProvider`, a lista combinada (local + web) por
  ///   trás da aba Favoritos.
  void toggleFavorite(Song song) {
    final newValue = !song.isFavorite;
    _repository.setFavorite(song.id, newValue);
    if (state.songs.any((s) => s.id == song.id)) {
      state = state.copyWith(
        songs: [
          for (final s in state.songs)
            if (s.id == song.id) s.copyWith(isFavorite: newValue) else s,
        ],
      );
    }
    _ref.read(queueControllerProvider.notifier).updateSongFavorite(song.id, newValue);
    _ref.read(favoritesNotifierProvider.notifier).loadFromDb();
  }

  /// Grava (ou atualiza) um resultado de busca do YouTube como uma
  /// linha de verdade no banco, sem alterar o favorito. Usado sempre
  /// que uma música da web precisa passar a existir como `Song` — ao
  /// tocar, adicionar à fila ou adicionar a uma playlist.
  ///
  /// [album]/[albumArtist]/[trackNumber] são opcionais e só vêm preenchidos
  /// quando a música sai de um álbum (aba Álbuns de um canal — ver
  /// `AlbumInstallNotifier`): é isso que faz um álbum instalado aparecer
  /// agrupado na tela Álbuns. Deixados em branco (o caso de qualquer
  /// resultado de busca comum), NÃO apagam um álbum já gravado antes —
  /// ver `LibraryRepository.upsertWebSong`.
  Song materializeWebSong(
    YoutubeSearchResult result, {
    String album = '',
    String albumArtist = '',
    int? trackNumber,
  }) {
    final song = Song(
      id: 0, // ignorado no upsert; o banco decide o id de verdade.
      path: 'youtube:${result.videoId}',
      title: result.title,
      artist: result.channelName,
      album: album,
      albumArtist: albumArtist,
      genre: '',
      year: null,
      trackNumber: trackNumber,
      durationMs: result.duration.inMilliseconds,
      coverPath: null,
      dateAdded: DateTime.now(),
      source: SongSource.youtube,
      remoteId: result.videoId,
      coverUrl: result.thumbnailUrl,
    );
    return _repository.upsertWebSong(song);
  }

  /// Favorita um resultado de busca que ainda não existe no banco —
  /// materializa (ver [materializeWebSong]) e favorita em seguida.
  /// Devolve o [Song] já persistido, para quem chamou poder, por
  /// exemplo, atualizar a fila com o id de verdade.
  Song materializeAndFavorite(YoutubeSearchResult result) {
    final song = materializeWebSong(result);
    toggleFavorite(song); // song.isFavorite começa false: isto favorita.
    return song;
  }
}

final libraryNotifierProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier(
    ref.watch(libraryRepositoryProvider),
    ref.watch(metadataServiceProvider),
    ref.watch(fileImportServiceProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(databaseProvider),
    ref,
  );
});
