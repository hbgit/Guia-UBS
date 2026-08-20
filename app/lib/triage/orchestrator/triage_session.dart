/// Driver da FSM-A: uma sessão de triagem, do primeiro toque ao cartão.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// A máquina decide, o driver executa. Nenhuma decisão clínica mora aqui:
/// severidade vem de [evaluate] e de [mergeVerdict], e as duas leem a mesma
/// tabela do pack.
///
/// ## O que esta classe garante sobre dados pessoais
///
/// Os tokens são dado sensível de saúde (art. 5º II; LGPD-RF13). Eles vivem em
/// um `Set` privado desta instância, **nunca** são gravados, logados ou
/// transmitidos, e [_clear] os remove ao fim da sessão. O [TriageResult] que
/// sai daqui não os carrega. O `sessionId` é sorteado por sessão e existe só
/// para correlacionar linhas do ring buffer local — não é identificador de
/// aparelho nem de pessoa, e morre junto com a sessão (LGPD-RF14).
library;

import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

import '../domain/routing_rule.dart';
import '../domain/severity.dart';
import '../engine/rule_only_engine.dart';
import '../engine/triage_engine.dart';
import '../gate/red_flag_gate.dart';
import 'triage_fsm.dart';

/// Teto de tokens por sessão (CAP-03).
const int maxSessionTokens = 5;

/// Inatividade que devolve a sessão ao repouso (linha A5).
const Duration sessionTimeout = Duration(seconds: 120);

/// Instantâneo do que a tela precisa desenhar.
@immutable
class TriageSnapshot {
  const TriageSnapshot({
    required this.state,
    required this.tokens,
    required this.result,
    required this.rejectedToken,
  });

  final TriageState state;

  /// Tokens escolhidos, em ordem de toque. Cópia imutável — a tela não
  /// consegue alterar a composição por referência.
  final List<String> tokens;

  /// Preenchido a partir de `s5Result` e `e1FailClosed`.
  final TriageResult? result;

  /// Último token recusado, para o retorno visual da linha A3. Some no toque
  /// seguinte.
  final String? rejectedToken;

  bool get isComposing => state == TriageState.s1Composing;
  bool get hasResult => result != null;
  bool get isFull => tokens.length >= maxSessionTokens;

  static const TriageSnapshot idle = TriageSnapshot(
    state: TriageState.s0Idle,
    tokens: [],
    result: null,
    rejectedToken: null,
  );
}

/// Uma sessão de triagem.
class TriageSession {
  TriageSession({
    required RuleModel model,
    required this.ontology,
    required TriageEngine engine,
    Random? random,
    this.idleTimeout = sessionTimeout,
  })  : _model = model,
        // ignore: prefer_initializing_formals — o nome público é `engine`.
        _engine = engine,
        _rules = RuleOnlyEngine(model),
        _random = random ?? Random.secure();

  final RuleModel _model;

  /// Ids de token que existem no pack ativo.
  ///
  /// Vem do `content/`, não do [RuleModel]: o modelo de regras conhece os
  /// tokens que alguma regra cita, e a ontologia é maior que isso. Validar
  /// contra as regras deixaria passar como "fora da ontologia" um sintoma
  /// legítimo que nenhuma regra menciona — e o desfecho padrão do pack existe
  /// justamente para esses casos.
  final Set<String> ontology;

  final TriageEngine _engine;
  final RuleOnlyEngine _rules;
  final Random _random;

  /// Tempo sem toque que descarta a sessão.
  final Duration idleTimeout;

  final _controller = StreamController<TriageSnapshot>.broadcast();

  TriageState _state = TriageState.s0Idle;

  /// **Dado sensível de saúde.** Só existe aqui, só em memória.
  final List<String> _tokens = [];

  TriageResult? _result;
  String? _rejected;
  String? _sessionId;
  Timer? _idleTimer;

  Stream<TriageSnapshot> get snapshots => _controller.stream;

  TriageSnapshot get snapshot => TriageSnapshot(
        state: _state,
        tokens: List.unmodifiable(_tokens),
        result: _result,
        rejectedToken: _rejected,
      );

  TriageState get state => _state;

  /// Id da sessão corrente. Sorteado a cada sessão, nunca persistido.
  String? get sessionId => _sessionId;

  // -------------------------------------------------------------------------
  // Entradas do usuário
  // -------------------------------------------------------------------------

  /// Começa uma triagem. Sem pack verificado, não começa (linha A1).
  void start({required bool packAvailable}) {
    if (!_fire(TapTriage(packAvailable: packAvailable))) return;
    _emit();
  }

  /// Toca um ícone de sintoma.
  ///
  /// Tokens duplicados são recusados: o conjunto que o gate avalia não tem
  /// repetição, e aceitar o mesmo ícone duas vezes gastaria uma das cinco
  /// vagas sem mudar nada no resultado.
  void addToken(String tokenId) {
    final known = ontology.contains(tokenId);
    final duplicate = _tokens.contains(tokenId);
    _fire(
      AddToken(
        inOntology: known && !duplicate,
        atCapacity: _tokens.length >= maxSessionTokens,
      ),
    );

    switch (_lastActions) {
      case [TriageAction.appendToken]:
        _tokens.add(tokenId);
        _rejected = null;
      case [TriageAction.rejectToken]:
        _rejected = tokenId;
      case _:
        return;
    }
    _restartIdleTimer();
    _emit();
  }

  /// Remove um token já escolhido.
  ///
  /// Não está na matriz da espec porque a matriz descreve a máquina, não a
  /// edição da composição: retirar um ícone tocado por engano mantém o estado
  /// em S1 e nenhuma guarda muda. Sem isto, errar um toque obrigaria a
  /// recomeçar a triagem — para quem não lê, recomeçar é caro.
  void removeToken(String tokenId) {
    if (_state != TriageState.s1Composing) return;
    if (!_tokens.remove(tokenId)) return;
    _rejected = null;
    _restartIdleTimer();
    _emit();
  }

  /// Confirma a composição e roda o caminho clínico até o resultado.
  Future<void> confirm() async {
    if (!_fire(Confirm(hasTokens: _tokens.isNotEmpty))) return;
    _cancelIdleTimer();
    _emit();
    await _evaluate();
  }

  /// Sai da tela de resultado, ou toca "casa" a qualquer momento.
  void abandon() {
    if (_state == TriageState.s0Idle) return;
    final event = _state == TriageState.s5Result ||
            _state == TriageState.e1FailClosed
        ? const LeaveResult()
        : const AbandonSession();
    if (!_fire(event)) return;
    _clear();
    _emit();
  }

  // -------------------------------------------------------------------------
  // Caminho clínico
  // -------------------------------------------------------------------------

  Future<void> _evaluate() async {
    final tokens = Set<String>.unmodifiable(_tokens);

    // ---- S2: gate determinístico, ANTES de qualquer inferência (INV-1) ----
    TriageVerdict verdict;
    try {
      verdict = evaluate(tokens, _model);
    } on Object {
      // Fail-closed. O avaliador é total e não deveria lançar — mas "não
      // deveria" não é garantia que se dê a um paciente. Pack inválido,
      // desfecho padrão ausente, o que for: a resposta é emergência.
      _fire(const GateFailed());
      _result = _emergencyResult();
      _emit();
      return;
    }
    final redFlag = isRedFlag(verdict, _model);
    _fire(
      GateDone(redFlag: redFlag, engineAvailable: _engine.isAvailable),
    );

    // ---- S5 direto: red flag não espera o modelo ----
    if (_state == TriageState.s5Result) {
      _result = mergeVerdict(verdict, null, degraded: false);
      _emit();
      return;
    }

    // ---- S3: modelo local, com teto de parede ----
    if (_state == TriageState.s3Inferring) {
      _emit();
      EngineSuggestion? suggestion;
      var failed = false;
      try {
        suggestion = await _engine.infer(tokens).timeout(_engine.timeout);
      } on Object {
        // O teto real de 5 s vive no C (ADR-002): um `timeout` no Dart
        // abandona a espera sem parar a CPU do aparelho. Este é o cinto de
        // segunda ordem, para o caso de o shim não devolver.
        failed = true;
      }
      if (!failed && suggestion != null) {
        _fire(const InferenceOk());
        _result = mergeVerdict(verdict, suggestion, degraded: false);
        _emit();
        return;
      }
      // Sem opinião do modelo também vai para o fallback: o resultado é o
      // mesmo do gate, mas a sessão fica marcada como degradada, e é isso que
      // a telemetria agregada precisa contar.
      _fire(const InferenceFailed());
    }

    // ---- S4: regras puras. Total, então sempre chega em S5 ----
    final fromRules = _rules.decide(tokens);
    _fire(const RulesDone());
    _result = mergeVerdict(verdict, fromRules, degraded: true);
    _emit();
  }

  /// Resultado do caminho fail-closed.
  ///
  /// Usa o desfecho de maior severidade **do pack**, não uma constante no
  /// código: o identificador de emergência é conteúdo revisado clinicamente, e
  /// escrevê-lo aqui criaria uma segunda fonte de verdade que sairia de
  /// sincronia na primeira republicação.
  TriageResult _emergencyResult() {
    final worst = _model.outcomes.values.reduce(
      (a, b) => b.severityLevel > a.severityLevel ? b : a,
    );
    return TriageResult(
      outcomeId: worst.id,
      severityLevel: worst.severityLevel,
      source: TriageSource.gate,
      degraded: true,
      matchedRuleId: null,
    );
  }

  // -------------------------------------------------------------------------
  // Mecânica
  // -------------------------------------------------------------------------

  List<TriageAction> _lastActions = const [];

  bool _fire(TriageEvent event) {
    final result = transition(_state, event);
    if (result == null) {
      _lastActions = const [];
      return false;
    }
    _state = result.next;
    _lastActions = result.actions;

    for (final action in result.actions) {
      switch (action) {
        case TriageAction.startSession:
          _clear();
          _sessionId = _newSessionId();
          _restartIdleTimer();
        case TriageAction.discardSession:
          _clear();
        case _:
          break;
      }
    }
    return true;
  }

  /// Id opaco de sessão, em memória (LGPD-RT03).
  String _newSessionId() {
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[_random.nextInt(16)]).join();
  }

  void _restartIdleTimer() {
    _cancelIdleTimer();
    _idleTimer = Timer(idleTimeout, abandon);
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Apaga a sessão da memória. É o cumprimento concreto da INV-2.
  void _clear() {
    _cancelIdleTimer();
    _tokens.clear();
    _result = null;
    _rejected = null;
    _sessionId = null;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(snapshot);
  }

  Future<void> dispose() async {
    _clear();
    await _controller.close();
  }
}
