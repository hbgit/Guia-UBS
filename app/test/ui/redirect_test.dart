/// Os dois portões que antecedem o conteúdo, exercitados como função pura.
///
/// O segundo portão é o que exige cuidado: ele implementa a **exceção única da
/// INV-8** (ADR-003). Exceção a invariante de segurança tem de ter o tamanho
/// exato do que foi autorizado — e "tamanho exato" é uma afirmação testável.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/sync/model_provisioning.dart';
import 'package:guia_ubs/ui/router_provider.dart';

String? redirect(
  String location, {
  AppLocale? locale = AppLocale.pt,
  SetupStage stage = SetupStage.ready,
  bool completed = true,
}) =>
    gubsRedirect(
      location: location,
      locale: locale,
      setupStage: stage,
      setupCompleted: completed,
    );

void main() {
  group('portão de idioma (RF-01)', () {
    test('sem idioma escolhido, tudo vai para a seleção', () {
      for (final path in ['/', '/onde-ir', '/documentos', '/triagem']) {
        expect(redirect(path, locale: null), languageGatePath);
      }
    });

    test('a própria tela de idioma não se redireciona — seria um laço', () {
      expect(redirect(languageGatePath, locale: null), isNull);
    });

    test('escolhido o idioma, a tela de seleção não volta a aparecer', () {
      expect(redirect(languageGatePath), '/');
    });
  });

  group('portão do modelo — exceção única da INV-8 (ADR-003)', () {
    test('setup já concluído não reabre a apresentação de valor', () {
      // A dívida que o item 11 paga: antes, `setupCompleted` vivia na memória
      // do processo, e quem escolheu "usar sem a IA assistente" revia a
      // apresentação de valor a cada abertura do app.
      expect(redirect('/', stage: SetupStage.blocked), isNull);
    });

    test('primeiro acesso abre no setup, para a apresentação de valor', () {
      expect(
        redirect('/', stage: SetupStage.awaitingConsent, completed: false),
        setupGatePath,
      );
    });

    test('depois de passar pelo setup, o conteúdo estático fica livre', () {
      // Este é o coração da exceção: a pessoa que usou a saída "sem a IA
      // assistente", ou cujo download falhou, continua com o app inteiro —
      // menos a triagem. Sem isto, uma falha de rede num posto rural deixaria
      // o app sem "Onde ir" e sem "Documentos", que são justamente o conteúdo
      // que a INV-8 protege e que não precisa de modelo nenhum.
      for (final path in ['/', '/onde-ir', '/documentos', '/fluxo', '/emergencia']) {
        expect(
          redirect(path, stage: SetupStage.blocked),
          isNull,
          reason: '$path ficou refém do modelo',
        );
      }
    });

    test('a triagem, sim, fica travada enquanto o modelo não está pronto', () {
      for (final path in ['/triagem', '/triagem/resultado']) {
        expect(redirect(path, stage: SetupStage.blocked), setupGatePath);
      }
    });

    for (final stage in SetupStage.values) {
      final blocking =
          stage != SetupStage.ready && stage != SetupStage.readyDegraded;
      test('estágio ${stage.name}: triagem ${blocking ? "travada" : "livre"}',
          () {
        expect(
          redirect('/triagem', stage: stage),
          blocking ? setupGatePath : isNull,
        );
      });
    }

    test('modo degradado libera a triagem — é a saída de emergência', () {
      // `readyDegraded` é quem tocou "usar sem a IA assistente". A triagem roda
      // pelo RuleOnlyEngine e continua clinicamente correta: o gate
      // determinístico decide sozinho e a INV-1 protege as emergências.
      expect(redirect('/triagem', stage: SetupStage.readyDegraded), isNull);
    });

    test('concluído o setup, a tela de setup devolve ao app', () {
      expect(redirect(setupGatePath, stage: SetupStage.ready), '/');
      expect(redirect(setupGatePath, stage: SetupStage.readyDegraded), '/');
    });

    test('durante o download, a tela de setup permanece', () {
      expect(redirect(setupGatePath, stage: SetupStage.downloading), isNull);
    });

    test('o portão de idioma vem antes do portão do modelo', () {
      // Mostrar consentimento de download de 1 GB em português para quem só
      // fala espanhol é pedir um "sim" que não é informado.
      expect(
        redirect('/', locale: null, stage: SetupStage.awaitingConsent, completed: false),
        languageGatePath,
      );
    });
  });

  test('nenhum redirect aponta para si mesmo', () {
    // Um redirect que devolve o próprio caminho é laço infinito no GoRouter.
    for (final path in [
      '/',
      '/idioma',
      '/configuracao',
      '/onde-ir',
      '/documentos',
      '/triagem',
    ]) {
      for (final locale in [null, AppLocale.pt]) {
        for (final stage in SetupStage.values) {
          for (final completed in [true, false]) {
            final target = redirect(
              path,
              locale: locale,
              stage: stage,
              completed: completed,
            );
            expect(
              target,
              isNot(path),
              reason: '$path com ${locale?.code}/${stage.name}/$completed',
            );
          }
        }
      }
    }
  });
}
