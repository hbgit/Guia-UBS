/// A CAP-02 pede três propriedades da navegação: bottom nav de 3 abas,
/// profundidade ≤ 4 e **zero dead-ends**. Como o mapa de rotas é dado
/// (`lib/ui/app_routes.dart`), as três viram travessias de lista.
///
/// Sem isto, "zero dead-ends" só seria descoberto em teste de usabilidade, com
/// uma pessoa presa numa tela sem saber sair — que é exatamente a situação que
/// este app existe para não criar.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_routes.dart';
import 'package:guia_ubs/ui/shell/app_shell.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';

void main() {
  final shellRoutes = gubsRoutes.where((r) => r.insideShell).toList();

  test('a navegação principal tem exatamente três abas', () {
    expect(GubsTab.values, hasLength(3));
  });

  test('toda aba tem uma rota que é a raiz dela', () {
    for (final tab in GubsTab.values) {
      expect(
        shellRoutes.where((r) => r.path == tab.rootPath),
        hasLength(1),
        reason: 'a aba ${tab.name} aponta para ${tab.rootPath}, que não existe',
      );
    }
  });

  test('nenhuma tela passa da profundidade máxima', () {
    for (final route in gubsRoutes) {
      expect(
        route.depth,
        lessThanOrEqualTo(maxNavigationDepth),
        reason: '${route.path} está a ${route.depth} níveis da raiz',
      );
    }
  });

  test('zero dead-ends: toda tela não-raiz tem um pai que existe', () {
    final paths = shellRoutes.map((r) => r.path).toSet();
    for (final route in shellRoutes) {
      final parent = route.parentPath;
      if (parent == null) continue;
      expect(
        paths,
        contains(parent),
        reason: '${route.path} volta para $parent, que não é uma tela',
      );
    }
  });

  test('toda tela da casca pertence a uma aba', () {
    // Uma tela sem aba dentro da casca deixaria a barra inteira apagada, e o
    // usuário sem indicação de onde está.
    for (final route in shellRoutes) {
      expect(route.tab, isNotNull, reason: '${route.path} não tem aba');
    }
  });

  test('a aba acesa é derivável de qualquer caminho', () {
    for (final route in shellRoutes) {
      expect(
        AppShell.tabFor(route.path),
        route.tab,
        reason: '${route.path} acenderia a aba errada',
      );
    }
  });

  test('caminho desconhecido cai na aba inicial, não em nenhuma', () {
    expect(AppShell.tabFor('/rota-que-nao-existe'), GubsTab.home);
  });

  test('nomes de rota são únicos', () {
    final names = gubsRoutes.map((r) => r.name).toList();
    expect(names.toSet(), hasLength(names.length));
  });

  test('caminhos são únicos', () {
    final paths = gubsRoutes.map((r) => r.path).toList();
    expect(paths.toSet(), hasLength(paths.length));
  });

  group('a exceção da INV-8 tem o tamanho exato do que o ADR-003 autorizou', () {
    test('só a triagem exige o modelo', () {
      final gated = gubsRoutes.where((r) => r.requiresModel).map((r) => r.path);

      expect(
        gated,
        unorderedEquals(['/triagem', '/triagem/sintomas', '/triagem/resultado']),
        reason: 'a trava do 1º acesso vale para a tela clínica, e só ela',
      );
    });

    test('conteúdo estático nunca depende do modelo', () {
      // "Onde ir", "Documentos" e o fluxo da UBS vêm do content.db e
      // funcionam igual com ou sem SLM. Travá-los seria violar a INV-8 sem
      // nenhuma autorização do ADR.
      for (final path in ['/onde-ir', '/documentos', '/fluxo', '/', '/emergencia']) {
        final spec = gubsRoutes.firstWhere((r) => r.path == path);
        expect(
          spec.requiresModel,
          isFalse,
          reason: '$path ficaria inacessível sem modelo',
        );
      }
    });

    test('a tela de emergência JAMAIS depende do modelo', () {
      // A mais importante das linhas acima, isolada: quem chega em
      // `/emergencia` pode estar tendo um infarto. Essa tela é conteúdo
      // estático assinado e não precisa de inferência nenhuma.
      expect(
        gubsRoutes.firstWhere((r) => r.path == '/emergencia').requiresModel,
        isFalse,
      );
    });
  });

  test('o roteador monta sem erro a partir do manifesto', () {
    final router = buildGubsRouter();
    addTearDown(router.dispose);

    expect(router.configuration.routes, isNotEmpty);
  });
}
