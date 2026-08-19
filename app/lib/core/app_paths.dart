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
Future<Directory> modelsDirectory() => _subdirectory('models');

/// Diretório dos pacotes de conteúdo (FSM-B): manifest ativo, packs nomeados
/// pelo hash e o estado auxiliar do sync.
///
/// Fica ao lado dos modelos, no mesmo filesystem — e isso importa: a troca de
/// pack é um `rename()`, que só é atômico dentro de um filesystem. Mover este
/// diretório para armazenamento externo quebraria a garantia do cenário S3 da
/// espec sem quebrar nenhum teste de host.
Future<Directory> packsDirectory() => _subdirectory('packs');

Future<Directory> _subdirectory(String name) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/$name');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}
