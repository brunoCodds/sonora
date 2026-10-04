import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models/spotify_track_ref.dart';
import '../security/secure_credentials_store.dart';

/// Cliente mínimo da Web API do Spotify, só para o que este app precisa:
/// ler o nome e as faixas de uma playlist pública. Nunca toca áudio —
/// isso é sempre resolvido no YouTube depois (ver
/// `PlaylistImportService`).
///
/// Usa o fluxo Client Credentials (`grant_type=client_credentials`):
/// autenticação de app-para-app com `client_id`+`client_secret`, sem
/// nenhum login de usuário. Isso é o que permite ler dados públicos
/// (busca, faixas de playlist) sem passar pelo teto de "5 usuários
/// autenticados" do Development Mode do Spotify (esse teto vale para
/// quem faz login via OAuth, o que não é o caso aqui). O único
/// pré-requisito, desde fev/2026, é a conta que registrou o app no
/// Spotify for Developers ter Spotify Premium.
class SpotifyClient {
  static const _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const _apiBase = 'https://api.spotify.com/v1';

  final SecureCredentialsStore _credentials;
  final http.Client _http;

  String? _accessToken;
  DateTime? _tokenExpiresAt;

  SpotifyClient(this._credentials, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Future<bool> get isConfigured => _credentials.hasSpotifyCredentials();

  /// Extrai o ID de uma playlist a partir de um link
  /// (`https://open.spotify.com/playlist/<id>?...`) ou de um ID puro já
  /// colado direto. Devolve `null` se não conseguir reconhecer nada.
  static String? extractPlaylistId(String urlOrId) {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.contains('spotify.com')) {
      final segments = uri.pathSegments;
      final index = segments.indexOf('playlist');
      if (index != -1 && index + 1 < segments.length) {
        return segments[index + 1];
      }
      return null;
    }

    // Assume que já é um ID puro.
    return trimmed;
  }

  static bool looksLikeSpotifyPlaylistLink(String text) {
    final trimmed = text.trim();
    return trimmed.contains('open.spotify.com/playlist');
  }

  Future<String?> getPlaylistName(String playlistId) async {
    final token = await _ensureAccessToken();
    final response = await _http.get(
      Uri.parse('$_apiBase/playlists/$playlistId?fields=name'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['name'] as String?;
  }

  /// Lê as faixas de uma playlist pública, paginando automaticamente
  /// (a API do Spotify devolve no máximo 100 por página). Faixas
  /// removidas/indisponíveis (`track: null`, comum em playlists
  /// colaborativas antigas) são ignoradas silenciosamente.
  Future<List<SpotifyTrackRef>> getPlaylistTracks(
    String playlistId, {
    int maxItems = 500,
  }) async {
    final token = await _ensureAccessToken();
    final tracks = <SpotifyTrackRef>[];

    String? nextUrl = '$_apiBase/playlists/$playlistId/tracks'
        '?limit=100&fields=next,items(track(name,artists(name),duration_ms))';

    while (nextUrl != null && tracks.length < maxItems) {
      final response = await _http.get(
        Uri.parse(nextUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw StateError(
          'Falha ao ler a playlist do Spotify (HTTP ${response.statusCode}). '
          'Confira se o link é de uma playlist pública.',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? []);

      for (final item in items) {
        final track = (item as Map<String, dynamic>)['track'] as Map<String, dynamic>?;
        final name = track?['name'] as String?;
        if (track == null || name == null) continue;

        final artists = (track['artists'] as List<dynamic>? ?? [])
            .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
        final durationMs = track['duration_ms'] as int?;

        tracks.add(SpotifyTrackRef(
          name: name,
          artists: artists,
          duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
        ));
      }

      nextUrl = data['next'] as String?;
    }

    return tracks;
  }

  Future<String> _ensureAccessToken() async {
    final expiresAt = _tokenExpiresAt;
    if (_accessToken != null && expiresAt != null && DateTime.now().isBefore(expiresAt)) {
      return _accessToken!;
    }

    final clientId = await _credentials.getSpotifyClientId();
    final clientSecret = await _credentials.getSpotifyClientSecret();
    if (clientId == null || clientId.isEmpty || clientSecret == null || clientSecret.isEmpty) {
      throw StateError(
        'Configure o Client ID e o Client Secret do Spotify em '
        'Configurações antes de importar uma playlist.',
      );
    }

    final basicAuth = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final response = await _http.post(
      Uri.parse(_tokenUrl),
      headers: {
        'Authorization': 'Basic $basicAuth',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'grant_type': 'client_credentials'},
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Falha ao autenticar com o Spotify (HTTP ${response.statusCode}). '
        'Confira o Client ID/Secret em Configurações, e se a conta usada '
        'para criar o app no Spotify for Developers tem Premium.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresInSeconds = data['expires_in'] as int? ?? 3600;
    // Margem de segurança de 1 minuto antes do token expirar de verdade.
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresInSeconds - 60));
    return _accessToken!;
  }
}
