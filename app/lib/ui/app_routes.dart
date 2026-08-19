/// O mapa de navegação, declarado como **dado**.
///
/// A CAP-02 pede três propriedades verificáveis: bottom nav de 3 abas,
/// profundidade ≤ 4 e **zero dead-ends**. Nenhuma delas é verificável olhando
/// uma árvore de `GoRoute` espalhada por builders — mas todas são triviais de
/// verificar percorrendo uma lista. Por isso as rotas moram aqui como
/// descrição, e [buildGubsRouter] apenas dobra essa lista num `GoRouter`.
///
/// É o mesmo movimento da FSM-B no item 9: quando o requisito é uma
/// propriedade da estrutura, a estrutura vira dado e o teste a percorre.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// As três abas da navegação principal.
enum GubsTab {
  home('/'),
  whereTo('/onde-ir'),
  documents('/documentos');

  const GubsTab(this.rootPath);

  /// Rota que a aba abre. É também o destino do botão "casa" daquela aba.
  final String rootPath;
}

/// Uma tela navegável.
@immutable
class GubsRouteSpec {
  const GubsRouteSpec({
    required this.path,
    required this.name,
    required this.tab,
    required this.builder,
    this.insideShell = true,
    this.requiresModel = false,
  });

  /// Caminho absoluto. Segmentos definem a profundidade.
  final String path;

  /// Nome estável para navegação por nome — sobrevive a mudança de caminho.
  final String name;

  /// Aba que fica acesa nesta tela. Telas fora da casca não têm aba.
  final GubsTab? tab;

  final Widget Function(BuildContext context, GoRouterState state) builder;

  /// `false` para portões que antecedem o app (idioma, provisionamento do
  /// modelo). Fora da casca não há bottom nav — de propósito: são telas com
  /// uma decisão a tomar, e oferecer navegação lateral ali seria oferecer
  /// saídas que não levam a lugar nenhum enquanto a decisão não for tomada.
  final bool insideShell;

  /// Se esta rota está sob a **exceção única da INV-8** (ADR-003).
  ///
  /// A trava do primeiro acesso vale para "a tela principal de atendimento
  /// clínico", e só. Marcar a lista inteira travaria também "Onde ir" e
  /// "Documentos" — conteúdo estático que a INV-8 protege explicitamente e que
  /// funciona sem modelo nenhum. Deixar isso como um campo por rota, em vez de
  /// um `if` no meio do redirect, é o que permite ao teste enumerar exatamente
  /// quais telas a exceção alcança.
  final bool requiresModel;

  /// Quantos segmentos abaixo da raiz.
  int get depth =>
      path == '/' ? 0 : path.split('/').where((s) => s.isNotEmpty).length;

  /// Caminho do pai, ou `null` quando não há para onde voltar.
  ///
  /// É isto que torna "zero dead-ends" uma propriedade checável — e é também o
  /// destino real do botão voltar (ver `shell/gubs_scaffold.dart`), porque o
  /// histórico de navegação não serve: as abas navegam com `go`, que substitui
  /// em vez de empilhar.
  ///
  /// Devolve `null` em dois casos, e a distinção importa:
  ///
  /// * **raiz de aba** — não é dead-end, é o topo. Uma seta ali levaria a lugar
  ///   nenhum e gastaria um dos oito elementos da tela;
  /// * **portão** (idioma, setup) — tem uma decisão pendente, e voltar dela
  ///   seria contornar a decisão.
  String? get parentPath {
    if (!insideShell) return null;
    if (GubsTab.values.any((tab) => tab.rootPath == path)) return null;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= 1) return GubsTab.home.rootPath;
    return '/${segments.sublist(0, segments.length - 1).join('/')}';
  }
}

/// Nomes das rotas, para não espalhar strings por telas.
abstract final class Routes {
  static const language = 'language';
  static const setup = 'setup';
  static const home = 'home';
  static const triageBody = 'triageBody';
  static const triageSymptoms = 'triageSymptoms';
  static const triageResult = 'triageResult';
  static const emergency = 'emergency';
  static const flow = 'flow';
  static const privacy = 'privacy';
  static const whereTo = 'whereTo';
  static const documents = 'documents';
}
