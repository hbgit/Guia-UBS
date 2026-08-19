/// Persistência do idioma escolhido (RF-01).
///
/// ## Por que isto não fere a INV-2
///
/// A INV-2 proíbe **dado pessoal do usuário final** em disco: a sequência de
/// sintomas morre em memória, e nada que identifique alguém é gravado. O
/// idioma da interface não é dado pessoal — é configuração do app, não
/// atributo da pessoa, fica só no aparelho e nunca sai dele. Um posto que
/// atende imigrantes hispanofalantes precisa que o aparelho abra em espanhol
/// na segunda vez; obrigar a escolher a cada abertura seria acessibilidade
/// pior sem nenhum ganho de privacidade.
///
/// ## Por que um arquivo e não um banco
///
/// O `prefs/` com Drift é o item 11 da Fase 2. Adiantá-lo aqui só para guardar
/// duas letras traria migração, geração de código e um banco a abrir no boot.
/// Este arquivo implementa a *porta* ([LocaleStore]) que o item 11 vai
/// reimplementar sobre Drift — a casca não sabe qual das duas está usando.
library;

import 'dart:convert';
import 'dart:io';

/// Idiomas que a casca suporta. Códigos ISO 639-1.
enum AppLocale {
  pt('pt'),
  es('es');

  const AppLocale(this.code);

  final String code;

  /// Converte um código, devolvendo `null` para desconhecido.
  static AppLocale? fromCode(String? code) {
    for (final locale in values) {
      if (locale.code == code) return locale;
    }
    return null;
  }
}

/// Onde o idioma escolhido é guardado.
abstract interface class LocaleStore {
  /// `null` quando o usuário ainda não escolheu — é o que faz a tela de
  /// idioma aparecer no primeiro acesso e nunca mais.
  Future<AppLocale?> read();

  Future<void> write(AppLocale locale);
}

/// Guarda em um JSON no diretório de suporte do app.
class FileLocaleStore implements LocaleStore {
  FileLocaleStore(this.file);

  final File file;

  @override
  Future<AppLocale?> read() async {
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return AppLocale.fromCode(decoded['locale'] as String?);
    } on Object {
      // Arquivo corrompido devolve "não escolhido", que faz o app perguntar de
      // novo. Lançar aqui travaria o boot por causa de uma preferência.
      return null;
    }
  }

  @override
  Future<void> write(AppLocale locale) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'locale': locale.code}),
        flush: true,
      );
    } on Object {
      // Sem espaço, sem permissão: a escolha vale para esta sessão e o app
      // pergunta de novo na próxima. Melhor que uma tela de erro.
    }
  }
}

/// Store em memória, para testes e para o caso de o disco estar indisponível.
class MemoryLocaleStore implements LocaleStore {
  MemoryLocaleStore([this._locale]);

  AppLocale? _locale;

  @override
  Future<AppLocale?> read() async => _locale;

  @override
  Future<void> write(AppLocale locale) async => _locale = locale;
}
