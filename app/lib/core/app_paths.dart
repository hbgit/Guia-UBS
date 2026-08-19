/// Onde o app guarda o que baixa.
///
/// `getApplicationSupportDirectory()` e não o diretório de documentos: o modelo
/// é um artefato de suporte da aplicação, não um documento do usuário. No
/// Android isso resolve para armazenamento INTERNO do app, o que traz três
/// consequências desejadas:
///
/// * não exige permissão de armazenamento;
/// * não aparece em galerias nem gerenciadores de arquivos, então o usuário não
///   apaga 800 MB por engano achando que é lixo;
/// * é removido junto com o app na desinstalação, sem deixar rastro.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Diretório dos modelos SLM, criado se necessário.
Future<Directory> modelsDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/models');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}
