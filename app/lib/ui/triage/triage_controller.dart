/// Estado da triagem para a UI.
///
/// A sessão ([TriageSession]) é quem decide; este arquivo só a expõe aos
/// widgets e cuida do que é de apresentação: qual passo da composição está na
/// tela, e disparar o áudio do resultado.
///
/// A sessão é criada **por triagem** e descartada ao final. Um objeto de sessão
/// que sobrevive entre triagens é um objeto que pode vazar os tokens de uma
/// pessoa para a próxima — e num posto de saúde o aparelho é compartilhado.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/domain/content_models.dart';
import '../../triage/domain/routing_rule.dart';
import '../../triage/engine/triage_engine.dart';
import '../../triage/orchestrator/triage_session.dart';
import '../app_scope.dart';

/// Passos da composição, na ordem em que aparecem.
///
/// Correspondem aos `kind` da ontologia do pack. Três passos, e não um só,
/// porque 26 ícones numa tela é o oposto do que a interface precisa ser: a
/// pessoa escolhe onde dói, depois o quê, depois como.
enum CompositionStep {
  bodyPart('body_part'),
  symptom('symptom'),
  modifier('modifier');

  const CompositionStep(this.tokenKind);

  final String tokenKind;

  CompositionStep? get next => switch (this) {
        CompositionStep.bodyPart => CompositionStep.symptom,
        CompositionStep.symptom => CompositionStep.modifier,
        CompositionStep.modifier => null,
      };

  CompositionStep? get previous => switch (this) {
        CompositionStep.bodyPart => null,
        CompositionStep.symptom => CompositionStep.bodyPart,
        CompositionStep.modifier => CompositionStep.symptom,
      };

  int get indexInFlow => CompositionStep.values.indexOf(this);
}

/// Motor de triagem ativo. `null` leva ao `RuleOnlyEngine` — o comportamento
/// correto quando não há modelo, e não um erro (RF-12).
///
/// **Começa nulo e é preenchido DEPOIS do boot**, quando houver modelo
/// verificado em disco. É `StateProvider` exatamente por isso: carregar um
/// `.gguf` de 800 MB leva segundos, e esperar por ele antes da primeira tela
/// travaria o app por causa de um componente que a INV-8 classifica como
/// opcional. Quem abrir a triagem nesses primeiros segundos roda por regras —
/// degradação, não falha.
///
/// A leitura acontece no INÍCIO da sessão (ver `_startSession`), então uma
/// sessão já em curso não troca de motor no meio.
final triageEngineProvider = StateProvider<TriageEngine?>((ref) => null);

/// Regras do pack ativo, ou `null` quando não há pack.
final ruleModelProvider = Provider<RuleModel?>((ref) {
  final content = ref.watch(contentProvider);
  if (content == null) return null;
  try {
    return content.ruleModel();
  } on Object {
    // Pack ilegível já foi recusado pelo `ActiveContent`; se ainda assim as
    // regras não carregarem, é melhor não ter triagem do que ter uma sem gate.
    return null;
  }
});

/// Ontologia do pack ativo — os ids que a composição aceita.
final ontologyProvider = Provider<Set<String>>((ref) {
  final content = ref.watch(contentProvider);
  if (content == null) return const {};
  return content.symptomTokens().map((t) => t.id).toSet();
});

/// `true` quando há pack verificado com regras — a guarda da linha A1.
final triageAvailableProvider = Provider<bool>(
  (ref) => ref.watch(ruleModelProvider) != null,
);

/// Tokens de um passo, já no idioma ativo.
final stepTokensProvider =
    Provider.family<List<SymptomToken>, CompositionStep>((ref, step) {
  final content = ref.watch(contentProvider);
  if (content == null) return const [];
  return content.symptomTokens(
    lang: ref.watch(contentLanguageProvider),
    kind: step.tokenKind,
  );
});

/// A sessão viva. `null` fora de uma triagem.
class TriageController extends StateNotifier<TriageSnapshot> {
  TriageController(this._ref) : super(TriageSnapshot.idle);

  final Ref _ref;

  TriageSession? _session;
  CompositionStep _step = CompositionStep.bodyPart;

  CompositionStep get step => _step;

  /// Abre uma sessão. Devolve `false` quando não há pack (linha A1).
  bool begin() {
    final model = _ref.read(ruleModelProvider);
    if (model == null) return false;

    _session?.dispose();
    _step = CompositionStep.bodyPart;

    final session = TriageSession(
      model: model,
      ontology: _ref.read(ontologyProvider),
      engine: _ref.read(triageEngineProvider) ?? const _UnavailableEngine(),
    );
    _session = session;
    session.snapshots.listen((snapshot) {
      if (mounted) state = snapshot;
    });
    session.start(packAvailable: true);
    state = session.snapshot;
    return true;
  }

  void toggleToken(String tokenId) {
    final session = _session;
    if (session == null) return;
    if (session.snapshot.tokens.contains(tokenId)) {
      session.removeToken(tokenId);
    } else {
      session.addToken(tokenId);
    }
  }

  /// Avança um passo da composição. Não é evento da FSM: a máquina permanece
  /// em S1 durante os três passos, porque compor é um estado só.
  void nextStep() {
    final next = _step.next;
    if (next != null) _step = next;
    state = _session?.snapshot ?? state;
  }

  void previousStep() {
    final previous = _step.previous;
    if (previous != null) _step = previous;
    state = _session?.snapshot ?? state;
  }

  Future<void> confirm() async => _session?.confirm();

  /// Encerra a sessão e apaga os tokens (INV-2).
  void finish() {
    _session?.abandon();
    _session?.dispose();
    _session = null;
    _step = CompositionStep.bodyPart;
    state = TriageSnapshot.idle;
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }
}

final triageControllerProvider =
    StateNotifierProvider<TriageController, TriageSnapshot>(
  TriageController.new,
);

/// Cartão do desfecho, resolvido no idioma ativo.
final resultCardProvider = Provider<ContentCard?>((ref) {
  final result = ref.watch(triageControllerProvider).result;
  final content = ref.watch(contentProvider);
  if (result == null || content == null) return null;
  return content.cardForOutcome(
    result.outcomeId,
    lang: ref.watch(contentLanguageProvider),
  );
});

/// Motor ausente. `isAvailable` falso leva a FSM direto ao fallback (linha A8).
class _UnavailableEngine implements TriageEngine {
  const _UnavailableEngine();

  @override
  String get id => 'unavailable';

  @override
  bool get isAvailable => false;

  @override
  Duration get timeout => Duration.zero;

  @override
  Future<EngineSuggestion?> infer(Set<String> tokens) async => null;

  @override
  Future<void> dispose() async {}
}

/// Fala o resultado. Fire-and-forget: a tela nunca espera o áudio.
///
/// Recebe a frase **já montada** por `resultAnnouncement` — a MESMA que o
/// leitor de tela anuncia, na mesma ordem: procedência, status, título,
/// orientação, e o aviso de falibilidade ao final.
///
/// Montar aqui uma segunda versão do texto criaria duas locuções para o mesmo
/// cartão, e a que ficasse para trás diria a alguém que a orientação veio de
/// outro lugar. Com uma fonte só, TalkBack e TTS não têm como divergir.
Future<void> speakAnnouncement(WidgetRef ref, String announcement) async {
  if (announcement.trim().isEmpty) return;
  final speaker = ref.read(speakerProvider);
  await speaker.speak(announcement, ref.read(speechLocaleProvider));
}
