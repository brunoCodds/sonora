import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda credenciais sensíveis (hoje, só Client ID/Secret do Spotify)
/// separadas do resto das preferências do app.
///
/// Diferente de `SettingsRepository` (que grava tudo em texto puro numa
/// tabela SQLite — ok para volume, pastas importadas, posição da
/// janela, etc.), aqui os valores são criptografados em repouso. No
/// Windows, o `flutter_secure_storage` grava um arquivo por chave,
/// cifrado (AES-GCM) com uma chave protegida pelo próprio SO, na pasta
/// de dados do app — bem diferente de uma string legível dentro do
/// `sonora_library.db`.
///
/// Requisito de ambiente: no Windows, o plugin nativo desse pacote
/// precisa dos componentes de C++ ATL do Visual Studio Build Tools
/// (workload "Desktop development with C++"). Se o `sqlite3_flutter_libs`
/// e o `media_kit` já compilam localmente, isso quase certamente já
/// está instalado.
class SecureCredentialsStore {
  static const _keySpotifyClientId = 'spotify_client_id';
  static const _keySpotifyClientSecret = 'spotify_client_secret';

  final FlutterSecureStorage _storage;

  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> getSpotifyClientId() => _storage.read(key: _keySpotifyClientId);

  Future<void> setSpotifyClientId(String? value) {
    if (value == null || value.isEmpty) {
      return _storage.delete(key: _keySpotifyClientId);
    }
    return _storage.write(key: _keySpotifyClientId, value: value);
  }

  Future<String?> getSpotifyClientSecret() =>
      _storage.read(key: _keySpotifyClientSecret);

  Future<void> setSpotifyClientSecret(String? value) {
    if (value == null || value.isEmpty) {
      return _storage.delete(key: _keySpotifyClientSecret);
    }
    return _storage.write(key: _keySpotifyClientSecret, value: value);
  }

  /// Verdadeiro quando os dois campos estão preenchidos — usado pela
  /// tela de Configurações para mostrar "configurado"/"não configurado",
  /// e pelo `PlaylistImportService` para decidir se tenta ou não
  /// resolver um link do Spotify.
  Future<bool> hasSpotifyCredentials() async {
    final id = await getSpotifyClientId();
    final secret = await getSpotifyClientSecret();
    return id != null && id.isNotEmpty && secret != null && secret.isNotEmpty;
  }

  Future<void> clearSpotifyCredentials() async {
    await setSpotifyClientId(null);
    await setSpotifyClientSecret(null);
  }
}
