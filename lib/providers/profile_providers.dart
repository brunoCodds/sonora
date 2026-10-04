import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// Nome e foto do usuário (tela de Perfil).
class ProfileState {
  /// Nome de usuário. Vazio = ainda não definido.
  final String name;

  /// Caminho da cópia local da foto (dentro da pasta de dados do app), ou
  /// `null` se o usuário ainda não escolheu uma.
  final String? photoPath;

  const ProfileState({this.name = '', this.photoPath});

  bool get hasPhoto => photoPath != null;

  ProfileState copyWith({String? name, String? photoPath, bool clearPhoto = false}) {
    return ProfileState(
      name: name ?? this.name,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final SettingsRepository _settings;

  ProfileNotifier(this._settings) : super(_load(_settings));

  static ProfileState _load(SettingsRepository settings) {
    var photo = settings.getString(AppConstants.keyProfilePhotoPath);
    // A foto pode ter sido apagada fora do app (limpeza de disco, etc.):
    // nesse caso volta ao avatar padrão em vez de apontar pra um arquivo
    // que não existe mais.
    if (photo != null && !File(photo).existsSync()) {
      settings.remove(AppConstants.keyProfilePhotoPath);
      photo = null;
    }
    return ProfileState(
      name: settings.getString(AppConstants.keyProfileName) ?? '',
      photoPath: photo,
    );
  }

  /// Guarda o nome (sem espaços nas pontas). Nome vazio remove a
  /// preferência. Chamado a cada alteração do campo de texto — gravar uma
  /// string curta no SQLite é barato, e assim nada se perde se o usuário
  /// sair da tela sem confirmar.
  void setName(String value) {
    final trimmed = value.trim();
    if (trimmed == state.name) return;
    state = state.copyWith(name: trimmed);
    if (trimmed.isEmpty) {
      _settings.remove(AppConstants.keyProfileName);
    } else {
      _settings.setString(AppConstants.keyProfileName, trimmed);
    }
  }

  /// Copia a imagem escolhida pra pasta de dados do app e passa a usar a
  /// cópia como foto de perfil (mesma ideia do cache de capas em
  /// `DownloadNotifier._cacheCoverArt`: o app não depende do arquivo
  /// original continuar onde estava). Devolve `false` se não conseguiu
  /// copiar — nesse caso a foto anterior continua valendo.
  ///
  /// Cada foto nova ganha um nome novo (com data/hora), e a anterior é
  /// apagada depois: se o nome fosse sempre o mesmo, o Flutter continuaria
  /// mostrando a imagem velha, que ele já guardou em cache pelo caminho.
  Future<bool> setPhotoFromFile(String sourcePath) async {
    try {
      final dir = await _profileDirectory();
      final extension = p.extension(sourcePath).toLowerCase();
      final target = File(p.join(
        dir.path,
        'avatar_${DateTime.now().millisecondsSinceEpoch}$extension',
      ));
      await File(sourcePath).copy(target.path);
      if (!mounted) return true;

      final previous = state.photoPath;
      _settings.setString(AppConstants.keyProfilePhotoPath, target.path);
      state = state.copyWith(photoPath: target.path);
      if (previous != null) await _deleteQuietly(previous);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Volta ao avatar padrão e apaga a cópia da foto.
  Future<void> removePhoto() async {
    final previous = state.photoPath;
    if (previous == null) return;
    _settings.remove(AppConstants.keyProfilePhotoPath);
    state = state.copyWith(clearPhoto: true);
    await _deleteQuietly(previous);
  }

  Future<Directory> _profileDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, AppConstants.profileDirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Só apaga arquivos que estão na pasta do perfil — nunca mexe num
  /// arquivo que o usuário tenha em outro lugar.
  Future<void> _deleteQuietly(String path) async {
    try {
      if (p.basename(p.dirname(path)) != AppConstants.profileDirName) return;
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Sobrar um arquivo antigo no disco não afeta nada.
    }
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier(ref.watch(settingsRepositoryProvider));
});
