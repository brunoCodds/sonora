import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../core/constants/supported_formats.dart';

/// Responsável por abrir os seletores nativos do sistema operacional e
/// por varrer pastas em busca de arquivos de áudio suportados.
///
/// Não sabe nada sobre metadados, banco de dados ou UI — apenas
/// devolve caminhos de arquivo.
class FileImportService {
  Future<List<String>> pickAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: SupportedFormats.audioExtensions,
      dialogTitle: 'Selecionar músicas',
    );
    if (result == null) return [];
    return result.files
        .map((f) => f.path)
        .whereType<String>()
        .where(SupportedFormats.isSupported)
        .toList();
  }

  Future<String?> pickFolder() async {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecionar pasta de músicas',
    );
  }

  /// Varre uma pasta recursivamente em busca de arquivos suportados.
  /// Ignora erros de leitura em subpastas específicas (ex: permissão
  /// negada) sem interromper a varredura inteira.
  List<String> scanFolder(String folderPath) {
    final found = <String>[];
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return found;

    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File && SupportedFormats.isSupported(entity.path)) {
          found.add(entity.path);
        }
      }
    } catch (_) {
      // Alguma subpasta pode ter falhado (permissão, link quebrado, etc).
      // O que já foi encontrado continua válido.
    }
    return found;
  }

  List<String> scanFolders(Iterable<String> folderPaths) {
    final all = <String>{};
    for (final folder in folderPaths) {
      all.addAll(scanFolder(folder));
    }
    return all.toList();
  }
}
