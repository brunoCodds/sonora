class AppConstants {
  AppConstants._();

  static const String appName = 'Sonora';
  static const String databaseFileName = 'sonora_library.db';
  static const String coversDirName = 'sonora_covers';
  static const String profileDirName = 'sonora_profile';

  // Chaves usadas na tabela `settings` (armazenamento chave/valor).
  static const String keyVolume = 'volume';
  static const String keyMuted = 'muted';
  static const String keyRepeatMode = 'repeat_mode';
  static const String keyShuffleEnabled = 'shuffle_enabled';
  static const String keySortField = 'sort_field';
  static const String keySortAscending = 'sort_ascending';
  static const String keyLastQueue = 'last_queue';
  static const String keyLastQueueIndex = 'last_queue_index';
  static const String keyLastPositionMs = 'last_position_ms';
  static const String keyImportFolders = 'import_folders';

  /// Pasta escolhida pelo usuário para as músicas da web baixadas. Ausente
  /// = usa a pasta padrão (ver `YoutubeDownloadService.defaultDownloadsPath`).
  static const String keyDownloadFolder = 'download_folder';
  static const String keyWindowWidth = 'window_width';
  static const String keyWindowHeight = 'window_height';
  static const String keyWindowPosX = 'window_pos_x';
  static const String keyWindowPosY = 'window_pos_y';
  static const String keyMiniWindowPosX = 'mini_window_pos_x';
  static const String keyMiniWindowPosY = 'mini_window_pos_y';
  static const String keyShortcutBindings = 'shortcut_bindings';

  // Tela de Perfil: identidade (nome/foto), tema e design do modo bandeira.
  static const String keyProfileName = 'profile_name';

  /// Caminho (dentro de [profileDirName]) da cópia da foto de perfil.
  static const String keyProfilePhotoPath = 'profile_photo_path';

  /// `AppPalette.id` da paleta escolhida (ver `AppPalettes.byId`).
  static const String keyThemePalette = 'theme_palette';

  /// `MiniPlayerLayout.name` do design do painel do modo bandeira.
  static const String keyMiniPlayerLayout = 'mini_player_layout';

  /// `MiniGlassStyle.name` — fundo do painel "Discreto".
  static const String keyMiniGlassStyle = 'mini_glass_style';

  /// Opacidade do fundo do painel "Discreto" (0 a 1; menor = mais transparente).
  static const String keyMiniGlassOpacity = 'mini_glass_opacity';

  static const double defaultWindowWidth = 1200;
  static const double defaultWindowHeight = 760;
  static const double minWindowWidth = 860;
  static const double minWindowHeight = 560;

  static const double playerBarHeight = 90;
  static const double sidebarWidth = 232;
}
