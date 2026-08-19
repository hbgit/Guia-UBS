/// Completude das traduções.
///
/// Uma chave que existe em `app_pt.arb` e falta em `app_es.arb` não quebra o
/// build: o Flutter cai no template. O resultado é uma tela em espanhol com
/// uma palavra em português no meio — exatamente para quem já tem menos
/// contexto para adivinhar o que ela significa. Este teste transforma esse
/// silêncio em falha.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

/// Chaves de tradução, sem os metadados (`@chave`, `@@locale`).
Set<String> _keys(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final pt = _arb('pt');
  final es = _arb('es');

  test('espanhol e português têm exatamente as mesmas chaves', () {
    final missingInEs = _keys(pt).difference(_keys(es));
    final extraInEs = _keys(es).difference(_keys(pt));

    expect(
      missingInEs,
      isEmpty,
      reason: 'sem tradução em espanhol, o app mostra português no meio da '
          'tela para quem não lê português',
    );
    expect(extraInEs, isEmpty, reason: 'chaves órfãs em espanhol');
  });

  test('nenhum valor é vazio', () {
    for (final (locale, arb) in [('pt', pt), ('es', es)]) {
      for (final key in _keys(arb)) {
        expect(
          (arb[key]! as String).trim(),
          isNotEmpty,
          reason: '$locale.$key está vazio',
        );
      }
    }
  });

  test('nenhuma tradução foi deixada igual ao português por esquecimento', () {
    // Algumas coincidem de verdade ("Documentos", "Continuar", "Guia UBS").
    // A lista abaixo é a exceção declarada; qualquer outra igualdade é
    // provavelmente copiar-e-colar que ninguém traduziu.
    const legitimatelyIdentical = {
      'appTitle',
      'homeDocuments',
      'documentsTitle',
      'actionContinue',
      'languagePortuguese',
      'languageSpanish',
      'navDocuments',
    };

    for (final key in _keys(pt)) {
      if (legitimatelyIdentical.contains(key)) continue;
      expect(
        es[key],
        isNot(pt[key]),
        reason: '$key é idêntico nos dois idiomas — traduzido ou esquecido?',
      );
    }
  });

  test('o app declara suporte aos dois idiomas, e só a eles', () {
    expect(
      L.supportedLocales.map((l) => l.languageCode),
      unorderedEquals(['pt', 'es']),
    );
  });

  testWidgets('as duas traduções carregam de verdade', (tester) async {
    for (final (code, expected) in [('pt', 'Início'), ('es', 'Inicio')]) {
      late L l;
      await tester.pumpWidget(
        Localizations(
          locale: Locale(code),
          delegates: const [
            L.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (context) {
              l = L.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(l.navHome, expected);
    }
  });
}
