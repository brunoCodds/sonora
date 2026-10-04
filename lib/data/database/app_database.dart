import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/constants/app_constants.dart';

/// Abre (criando se necessário) o banco SQLite local da aplicação.
///
/// Optamos por usar o pacote `sqlite3` diretamente, com SQL simples e
/// explícito nos repositórios, em vez de um ORM com geração de código
/// (como drift). Isso mantém o projeto 100% compilável apenas com
/// `flutter pub get`, sem depender de `build_runner`.
class AppDatabase {
  final Database db;

  AppDatabase._(this.db);

  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final dbPath = p.join(dir.path, AppConstants.databaseFileName);

    try {
      return AppDatabase._(_openAndConfigure(dbPath));
    } catch (_) {
      // Se o processo anterior foi encerrado abruptamente (ex.: crash
      // nativo do engine) o arquivo do banco, o WAL ou o journal podem
      // ficar num estado inconsistente e impedir a abertura na próxima
      // vez que o app iniciar — o app fecharia sozinho assim que fosse
      // aberto, sem nenhuma tela chegar a aparecer. Em vez de propagar a
      // exceção e derrubar o app na inicialização, tenta uma vez
      // descartar os arquivos do banco e recriar do zero.
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('$dbPath$suffix');
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {
            // Ignora: se não conseguir apagar, a segunda tentativa de
            // abrir abaixo vai falhar e propagar o erro original.
          }
        }
      }
      return AppDatabase._(_openAndConfigure(dbPath));
    }
  }

  static Database _openAndConfigure(String dbPath) {
    final db = sqlite3.open(dbPath);
    // Tempo de espera antes de lançar SQLITE_BUSY em vez de falhar na
    // hora: evita erros espúrios se outro processo (ex.: uma instância
    // anterior ainda finalizando) segurar o arquivo por um instante.
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA foreign_keys = ON;');
    // WAL é mais resistente a deixar o banco num estado inconsistente
    // caso o app seja encerrado abruptamente no meio de uma escrita.
    db.execute('PRAGMA journal_mode = WAL;');
    _createSchema(db);
    return db;
  }

  static void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        album_artist TEXT NOT NULL,
        genre TEXT NOT NULL,
        year INTEGER,
        track_number INTEGER,
        duration_ms INTEGER NOT NULL,
        cover_path TEXT,
        date_added INTEGER NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'local',
        remote_id TEXT,
        cover_url TEXT,
        local_path TEXT
      );
    ''');

    // `CREATE TABLE IF NOT EXISTS` acima só cria as colunas novas em
    // bancos criados a partir de agora — quem já usava o app antes
    // delas existirem continua com a tabela do jeito que estava, já
    // que o CREATE vira um no-op nesse caso. Sem essa migração, essas
    // pessoas quebrariam ao tentar favoritar uma música (is_favorite)
    // ou ao abrir a busca na web (source/remote_id/cover_url/local_path).
    _migrateSchema(db);

    db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        song_id INTEGER NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
        position INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist ON playlist_songs(playlist_id);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_songs_album ON songs(album, album_artist);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs(artist);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_songs_source ON songs(source);',
    );
  }

  /// Adiciona, em bancos que já existiam antes dela, colunas que só
  /// passaram a existir em versões mais novas do app. Cada checagem aqui
  /// é idempotente (não faz nada se a coluna já existir), então é
  /// seguro chamar isso toda vez que o app abre.
  static void _migrateSchema(Database db) {
    final columns = db.select('PRAGMA table_info(songs);');
    bool hasColumn(String name) => columns.any((row) => row['name'] == name);

    if (!hasColumn('is_favorite')) {
      db.execute('ALTER TABLE songs ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;');
    }
    if (!hasColumn('source')) {
      db.execute("ALTER TABLE songs ADD COLUMN source TEXT NOT NULL DEFAULT 'local';");
    }
    if (!hasColumn('remote_id')) {
      db.execute('ALTER TABLE songs ADD COLUMN remote_id TEXT;');
    }
    if (!hasColumn('cover_url')) {
      db.execute('ALTER TABLE songs ADD COLUMN cover_url TEXT;');
    }
    if (!hasColumn('local_path')) {
      db.execute('ALTER TABLE songs ADD COLUMN local_path TEXT;');
    }
  }

  Future<Directory> coversDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(dir.path, AppConstants.coversDirName));
    if (!coversDir.existsSync()) {
      coversDir.createSync(recursive: true);
    }
    return coversDir;
  }

  void close() => db.dispose();
}
