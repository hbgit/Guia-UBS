/// O roteador do app, com os dois portões que antecedem o conteúdo.
///
/// ## Portão 1 — idioma (RF-01)
///
/// Sem idioma escolhido não há como rotular nada, então tudo vai para
/// `/idioma`. Acontece uma vez na vida do aparelho: a escolha é persistida.
///
/// ## Portão 2 — modelo SLM (exceção única da INV-8, ADR-003)
///
/// Este é o portão que exige cuidado. A INV-8 diz que falha de LLM, TTS ou
/// sync **nunca** impede navegação de conteúdo estático; o ADR-003 abriu uma
/// exceção, e exceção a invariante de segurança precisa ser do tamanho exato
/// do que foi autorizado — nem um caminho a mais.
///
/// O que foi autorizado: travar *"a tela principal de atendimento clínico"* até
/// o modelo estar baixado e verificado. Logo, o portão fecha apenas as rotas
/// marcadas com `requiresModel` — a triagem. "Onde ir", "Documentos" e o
/// fluxo da UBS continuam abertos sem modelo nenhum, porque são exatamente o
/// conteúdo estático que a INV-8 protege e que funciona igual com ou sem SLM.
///
/// No **primeiro** acesso o app ainda abre direto no setup, para que a
/// apresentação de valor e o pedido de consentimento aconteçam. A diferença é
/// que, a partir do momento em que a pessoa sai dali — concluindo o download ou
/// usando a saída "sem a IA assistente" —, o resto do app nunca mais fica
/// refém do modelo.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../prefs/locale_store.dart';
import '../sync/model_provisioning.dart';
import 'app_router.dart';
import 'app_scope.dart';

/// Caminhos dos portões.
const String languageGatePath = '/idioma';
const String setupGatePath = '/configuracao';

/// Decide para onde mandar quem pediu [location].
///
/// Função pura: é ela que os testes exercitam, sem inflar widget nenhum.
String? gubsRedirect({
  required String location,
  required AppLocale? locale,
  required SetupStage setupStage,
  required bool setupCompleted,
}) {
  if (locale == null) {
    return location == languageGatePath ? null : languageGatePath;
  }
  if (location == languageGatePath) return '/';

  final blocking = setupStage != SetupStage.ready &&
      setupStage != SetupStage.readyDegraded;

  if (location == setupGatePath) {
    // Terminou (ou desistiu): sai do portão. Ficar aqui deixaria a pessoa
    // olhando uma barra de progresso concluída sem saída.
    return blocking ? null : '/';
  }

  // Primeira passagem: mostra a apresentação de valor e o pedido de
  // consentimento. `setupCompleted` vem do `user.db` (item 11), não da memória
  // do processo: antes disso, quem escolhia "usar sem a IA assistente" via a
  // apresentação de valor de novo a cada abertura do app, como se a decisão
  // nunca tivesse sido tomada.
  if (blocking && !setupCompleted) return setupGatePath;

  final spec = gubsRoutes.where((r) => r.path == location).firstOrNull;
  if (blocking && (spec?.requiresModel ?? false)) return setupGatePath;

  return null;
}

/// Roteador construído uma vez, realimentado pelos providers.
final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter reavalia o redirect quando este `Listenable` avisa. Sem ele, o
  // app ficaria parado na tela de idioma depois de escolher — o estado mudaria
  // e ninguém pediria a reavaliação.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  ref.listen(localeControllerProvider, (_, _) => refresh.value++);
  ref.listen(setupStateProvider, (_, _) => refresh.value++);
  ref.listen(setupCompletedProvider, (_, _) => refresh.value++);

  return buildGubsRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (location) {
      final stage = ref.read(setupStateProvider).valueOrNull?.stage ??
          SetupStage.checking;
      return gubsRedirect(
        location: location,
        locale: ref.read(localeControllerProvider),
        setupStage: stage,
        setupCompleted: ref.read(setupCompletedProvider),
      );
    },
  );
});
