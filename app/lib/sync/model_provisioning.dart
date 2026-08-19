/// Provisionamento do modelo SLM — o "First-Time Setup" com trava de operação.
///
/// ===========================================================================
/// TENSÃO DELIBERADA COM A INV-8 — LEIA ANTES DE MEXER
/// ===========================================================================
///
/// A INV-8 diz que falha de LLM/TTS/sync **nunca** impede navegação, e o RF-12
/// existe para que um aparelho sem modelo continue atendendo pelo
/// `RuleOnlyEngine`. Esta classe implementa o oposto durante o PRIMEIRO acesso:
/// bloqueia a tela clínica até o modelo estar baixado e verificado.
///
/// A decisão é do produto (ADR-003 + onboarding assistido) e o racional é que
/// um agente de saúde configura o aparelho uma vez, com Wi-Fi da UBS, fora de
/// atendimento. O risco que ela aceita é real: num posto sem Wi-Fi, o app fica
/// inutilizável em vez de degradado.
///
/// Por isso a trava tem DUAS saídas explícitas, e nenhuma delas é escondida:
///
/// * [importFromLocalFile] — pendrive/OTG, para postos sem rede utilizável;
/// * [allowMeteredNetworks] — override do administrador, para urgência.
///
/// A trava vale só para `SetupStage.blocked`. Uma vez concluída, o app volta a
/// obedecer a INV-8 integralmente: se o modelo sumir ou corromper depois, a
/// triagem degrada para regras sem bloquear ninguém.
library;

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import 'model_downloader.dart';
import 'resumable_downloader.dart';

/// Classe de rede vista pelo app. `unmetered` = Wi-Fi ou cabo.
enum NetworkClass { unmetered, metered, none }

/// Etapas do setup inicial. A UI é uma função deste estado.
enum SetupStage {
  /// Conferindo rede e espaço em disco.
  checking,

  /// Pronto para baixar, aguardando o "sim" do usuário.
  awaitingConsent,

  /// Transferindo. `progress` está preenchido.
  downloading,

  /// Baixado; conferindo SHA-256 antes de aceitar.
  verifying,

  /// Modelo pronto. A tela clínica libera com o SLM disponível.
  ready,

  /// O usuário optou por seguir SEM o modelo. A tela clínica libera em modo
  /// degradado (`RuleOnlyEngine`).
  ///
  /// Distinto de [ready] de propósito: o orquestrador precisa saber que não há
  /// SLM para escolher o motor, e a telemetria precisa saber que este aparelho
  /// está numa coorte diferente.
  readyDegraded,

  /// Não foi possível prosseguir agora. `blockReason` explica.
  blocked,
}

/// Por que o setup não pode prosseguir — texto de UI deriva daqui.
enum SetupBlockReason {
  /// Sem rede alguma.
  offline,

  /// Só dados móveis, e o override não foi ligado.
  meteredOnly,

  /// Menos de 3 GB livres.
  insufficientDiskSpace,

  /// Transferência interrompida; o progresso foi preservado.
  interrupted,

  /// Arquivo não confere com o hash esperado.
  integrityFailed,
}

@immutable
class SetupState {
  const SetupState({
    required this.stage,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.blockReason,
    this.detail,
  });

  final SetupStage stage;
  final int receivedBytes;
  final int totalBytes;
  final SetupBlockReason? blockReason;
  final String? detail;

  /// Porcentagem inteira 0–100, ou `null` quando o total é desconhecido —
  /// caso em que a UI deve mostrar progresso indeterminado, não "0%".
  int? get percent {
    if (totalBytes <= 0) return null;
    return ((receivedBytes / totalBytes) * 100).clamp(0, 100).floor();
  }

  /// A trava de operação. `true` enquanto a tela clínica deve ficar fechada.
  bool get blocksClinicalScreen =>
      stage != SetupStage.ready && stage != SetupStage.readyDegraded;

  /// `true` quando o app opera sem SLM — o orquestrador usa `RuleOnlyEngine`.
  bool get isDegraded => stage == SetupStage.readyDegraded;

  SetupState copyWith({
    SetupStage? stage,
    int? receivedBytes,
    int? totalBytes,
    SetupBlockReason? blockReason,
    String? detail,
  }) =>
      SetupState(
        stage: stage ?? this.stage,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        blockReason: blockReason,
        detail: detail,
      );
}

/// Orquestra o setup inicial do modelo.
///
/// Não conhece Flutter nem plugins: rede e diretório entram por injeção, o que
/// mantém toda a política testável sem aparelho.
class ModelProvisioning {
  ModelProvisioning({
    required this.artifact,
    required this.destinationDirectory,
    required this.networkClass,
    ResumableDownloader? downloader,
    this.requiredFreeBytes = 3 * 1024 * 1024 * 1024,
  }) : _downloader = downloader ?? ResumableDownloader();

  final ModelArtifact artifact;
  /// Onde gravar o modelo. Injetado para manter esta classe livre de plugins.
  final Future<Directory> Function() destinationDirectory;

  /// Classe da rede corrente.
  final Future<NetworkClass> Function() networkClass;
  final ResumableDownloader _downloader;
  final int requiredFreeBytes;

  final _states = StreamController<SetupState>.broadcast();

  SetupState _state = const SetupState(stage: SetupStage.checking);

  /// Estado corrente. A tela pode ler direto ou ouvir [states].
  SetupState get state => _state;

  /// Fluxo de estados para a UI.
  Stream<SetupState> get states => _states.stream;

  /// Override do administrador: permite baixar por dados móveis.
  ///
  /// Existe para urgência — uma UBS sem Wi-Fi que precisa do app hoje. Não é
  /// padrão porque 800 MB em plano de dados de agente comunitário é um custo
  /// que ninguém pediu.
  bool allowMeteredNetworks = false;

  void _emit(SetupState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<File> _destinationFile() async =>
      File('${(await destinationDirectory()).path}/${artifact.fileName}');

  /// Marcador de "este arquivo já foi verificado".
  ///
  /// Guarda tamanho e data de modificação do arquivo no momento em que o
  /// SHA-256 conferiu. Enquanto os dois baterem, confiamos sem reler.
  File _markerFor(File model) => File('${model.path}.verificado');

  Future<void> _writeMarker(File model) async {
    try {
      final stat = model.statSync();
      await _markerFor(model)
          .writeAsString('${stat.size}:${stat.modified.microsecondsSinceEpoch}');
    } on Object {
      // Sem marcador, o pior que acontece é reverificar na próxima abertura.
    }
  }

  /// `true` quando o arquivo casa com o marcador gravado após a verificação.
  ///
  /// ===========================================================================
  /// POR QUE NÃO REVERIFICAR O HASH A CADA ABERTURA
  /// ===========================================================================
  ///
  /// Medido no aparelho: SHA-256 de 806 MB custa ~1,3 s em código nativo, mas o
  /// `package:crypto` é Dart puro e roda ~9× mais devagar — cerca de **12 s**.
  /// Reverificar a cada boot significaria travar a tela clínica por 12 s toda
  /// vez, num app cujo propósito é orientar alguém que pode estar passando mal.
  ///
  /// Isso também violaria a própria exceção registrada na INV-8, que autoriza a
  /// trava **apenas no primeiro provisionamento**.
  ///
  /// Tamanho + mtime pegam os casos realistas: truncamento, substituição do
  /// arquivo, download interrompido. Não pegam corrupção silenciosa de bits com
  /// mtime preservado — para essa, o custo é o carregamento falhar no llama.cpp
  /// e o app degradar para `RuleOnlyEngine`, que é degradação, não dano.
  bool _matchesMarker(File model) {
    try {
      final marker = _markerFor(model);
      if (!marker.existsSync()) return false;
      final parts = marker.readAsStringSync().split(':');
      if (parts.length != 2) return false;
      final stat = model.statSync();
      return parts[0] == '${stat.size}' &&
          parts[1] == '${stat.modified.microsecondsSinceEpoch}';
    } on Object {
      return false;
    }
  }

  /// Passo 1 do onboarding: checa pré-requisitos e decide se pode pedir o "sim".
  ///
  /// Não baixa nada. Se o modelo já estiver em disco, pula direto para pronto —
  /// reinstalar o app não deve custar 800 MB de novo se o arquivo sobreviveu.
  Future<SetupState> checkPrerequisites() async {
    _emit(const SetupState(stage: SetupStage.checking));

    final destination = await _destinationFile();
    if (destination.existsSync()) {
      // Caminho rápido: já verificamos este arquivo antes e ele não mudou.
      if (_matchesMarker(destination)) {
        _emit(SetupState(
          stage: SetupStage.ready,
          receivedBytes: artifact.sizeBytes,
          totalBytes: artifact.sizeBytes,
        ));
        return _state;
      }
      // Primeira vez, ou o arquivo mudou: confere o hash de verdade.
      _emit(const SetupState(stage: SetupStage.verifying));
      return _fetch(destination, null);
    }

    final network = await networkClass();
    if (network == NetworkClass.none) {
      _emit(const SetupState(
        stage: SetupStage.blocked,
        blockReason: SetupBlockReason.offline,
      ));
      return _state;
    }
    if (network == NetworkClass.metered && !allowMeteredNetworks) {
      _emit(const SetupState(
        stage: SetupStage.blocked,
        blockReason: SetupBlockReason.meteredOnly,
      ));
      return _state;
    }

    _emit(SetupState(
      stage: SetupStage.awaitingConsent,
      totalBytes: artifact.sizeBytes,
    ));
    return _state;
  }

  /// Passo 2: o usuário disse "sim". Baixa em primeiro plano, reportando %.
  ///
  /// Só faz sentido a partir de [SetupStage.awaitingConsent] ou de um bloqueio
  /// retentável — chamar em outro estado é ruído de UI e é ignorado.
  Future<SetupState> startDownload() async {
    if (_state.stage == SetupStage.downloading ||
        _state.stage == SetupStage.ready) {
      return _state;
    }

    final destination = await _destinationFile();
    _emit(SetupState(
      stage: SetupStage.downloading,
      totalBytes: artifact.sizeBytes,
    ));

    return _fetch(destination, (received, total) {
      // Só emite em progresso: o `verifying` que vem depois não deve ser
      // sobrescrito por um evento atrasado da transferência.
      if (_state.stage != SetupStage.downloading) return;
      _emit(SetupState(
        stage: SetupStage.downloading,
        receivedBytes: received,
        totalBytes: total,
      ));
    });
  }

  Future<SetupState> _fetch(File destination, DownloadProgress? onProgress) async {
    final downloader = ModelDownloader(
      artifact: artifact,
      destination: destination,
      downloader: _downloader,
      requiredFreeBytes: requiredFreeBytes,
    );

    final result = await downloader.ensureAvailable(onProgress: onProgress);

    switch (result) {
      case ModelReady():
        await _writeMarker(destination);
        _emit(SetupState(
          stage: SetupStage.ready,
          receivedBytes: artifact.sizeBytes,
          totalBytes: artifact.sizeBytes,
        ));
      case ModelUnavailable(:final reason, :final detail, :final bytesSoFar):
        _emit(SetupState(
          stage: SetupStage.blocked,
          receivedBytes: bytesSoFar,
          totalBytes: artifact.sizeBytes,
          blockReason: switch (reason) {
            ModelUnavailableReason.insufficientDiskSpace =>
              SetupBlockReason.insufficientDiskSpace,
            ModelUnavailableReason.interrupted => SetupBlockReason.interrupted,
            ModelUnavailableReason.rejected => SetupBlockReason.integrityFailed,
          },
          detail: detail,
        ));
    }
    return _state;
  }

  /// Saída de emergência: seguir sem o modelo, em modo degradado.
  ///
  /// ===========================================================================
  /// POR QUE ISTO EXISTE
  /// ===========================================================================
  ///
  /// A trava de operação assume que o agente configura o aparelho com Wi-Fi da
  /// UBS, fora de atendimento. Quando essa suposição falha — posto sem rede,
  /// sem pendrive, e alguém precisando de orientação AGORA — travar o app é
  /// pior que degradá-lo: o gate determinístico sozinho já dá orientação
  /// clínica correta (INV-1 protege as emergências), e negar isso não protege
  /// ninguém.
  ///
  /// **Não é desistir do modelo.** O agendador em segundo plano continua
  /// tentando baixar quando houver Wi-Fi; ao concluir, o app volta a [ready]
  /// sozinho. Esta é uma decisão sobre AGORA, não sobre sempre.
  ///
  /// Só faz sentido a partir de um bloqueio: sair do fluxo antes de saber se há
  /// impedimento seria pular o setup por acidente.
  SetupState continueWithoutModel() {
    if (_state.stage != SetupStage.blocked) return _state;
    _emit(SetupState(
      stage: SetupStage.readyDegraded,
      receivedBytes: _state.receivedBytes,
      totalBytes: _state.totalBytes,
      detail: 'usuario optou por seguir sem o modelo',
    ));
    return _state;
  }

  /// Saída alternativa: importar o modelo de um pendrive/OTG ou do cartão.
  ///
  /// Feito para o posto que não tem rede utilizável: alguém leva o arquivo num
  /// pendrive. **O SHA-256 é conferido igual** — a procedência do arquivo não
  /// muda o que exigimos dele. Um pendrive que passou por dez mãos não é mais
  /// confiável que um espelho HTTP.
  Future<SetupState> importFromLocalFile(File source) async {
    _emit(const SetupState(stage: SetupStage.verifying));

    if (!source.existsSync()) {
      _emit(const SetupState(
        stage: SetupStage.blocked,
        blockReason: SetupBlockReason.integrityFailed,
        detail: 'arquivo de origem inexistente',
      ));
      return _state;
    }

    final destination = await _destinationFile();
    try {
      // Copia para um parcial e deixa o downloader fazer a verificação: um só
      // caminho de aceite no sistema inteiro, sem atalho para o modo offline.
      final staging = File('${destination.path}.parcial');
      if (destination.existsSync()) await destination.delete();
      await source.copy(staging.path);
    } on Object catch (error) {
      _emit(SetupState(
        stage: SetupStage.blocked,
        blockReason: SetupBlockReason.insufficientDiskSpace,
        detail: '$error',
      ));
      return _state;
    }

    // `fetch` encontra o parcial completo; a verificação decide. Se o hash
    // bater, nem sequer há rede envolvida.
    return _fetch(destination, null);
  }

  Future<void> dispose() async {
    _downloader.close();
    await _states.close();
  }
}
