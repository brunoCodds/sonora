import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';

/// Armazenamento simples de chave/valor usado para preferências,
/// volume, modo de repetição, última fila reproduzida, pastas de
/// importação, tamanho da janela etc.
class SettingsRepository {
  final Database _db;

  SettingsRepository(AppDatabase database) : _db = database.db;

  String? getString(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  void setString(String key, String value) {
    _db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  double getDouble(String key, {double fallback = 0}) {
    final raw = getString(key);
    if (raw == null) return fallback;
    return double.tryParse(raw) ?? fallback;
  }

  void setDouble(String key, double value) => setString(key, value.toString());

  int getInt(String key, {int fallback = 0}) {
    final raw = getString(key);
    if (raw == null) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  void setInt(String key, int value) => setString(key, value.toString());

  bool getBool(String key, {bool fallback = false}) {
    final raw = getString(key);
    if (raw == null) return fallback;
    return raw == 'true';
  }

  void setBool(String key, bool value) => setString(key, value.toString());

  List<int> getIntList(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e as int).toList();
    } catch (_) {
      return [];
    }
  }

  void setIntList(String key, List<int> values) {
    setString(key, jsonEncode(values));
  }

  List<String> getStringList(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e as String).toList();
    } catch (_) {
      return [];
    }
  }

  void setStringList(String key, List<String> values) {
    setString(key, jsonEncode(values));
  }

  void remove(String key) {
    _db.execute('DELETE FROM settings WHERE key = ?', [key]);
  }
}
