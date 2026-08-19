/// Onboarding assistido com trava de operação (ADR-003).
///
/// A tela é uma FUNÇÃO do `SetupState`: toda a decisão mora em
/// `ModelProvisioning`, e aqui só se escolhe o que desenhar. É o que permite
/// testar o fluxo inteiro sem inflar um widget.
///
/// Cor segue a semântica fixa do projeto — azul = informação, vermelho =
/// impedimento. Verde é reservado a UBS/rotina e não aparece aqui.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../sync/model_provisioning.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.provisioning,
    required this.onReady,
    this.pickLocalModel,
    super.key,
  });

  final ModelProvisioning provisioning;

  /// Chamado quando a trava libera. Só então a tela clínica pode abrir.
  final VoidCallback onReady;

  /// Seletor de arquivo para importação por pendrive/OTG. Injetado para que a
  /// tela não dependa do plugin de picker.
  final Future<File?> Function()? pickLocalModel;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    widget.provisioning.checkPrerequisites();
  }

  Future<void> _importFromStorage() async {
    final picker = widget.pickLocalModel;
    if (picker == null) return;
    final file = await picker();
    if (file != null) await widget.provisioning.importFromLocalFile(file);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SetupState>(
      stream: widget.provisioning.states,
      initialData: widget.provisioning.state,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        if (!state.blocksClinicalScreen) {
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady());
        }
        return Scaffold(
          // Rolagem obrigatória, não decorativa: em paisagem — e com a fonte
          // ampliada, que é o caso comum do nosso público (RNF-06) — o conteúdo
          // do estado bloqueado não cabe na altura. Sem isto, o botão "Usar sem
          // a IA assistente" fica FORA da tela, e a saída de emergência some
          // justamente na tela em que ela existe.
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  // Ocupa a altura toda quando sobra espaço, para o conteúdo
                  // seguir centralizado; rola quando falta.
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: IntrinsicHeight(child: _body(context, state)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, SetupState state) {
    return switch (state.stage) {
      SetupStage.checking => const _Centered(
          icon: Icons.wifi_find,
          title: 'Preparando o aplicativo',
          message: 'Verificando conexão e espaço disponível…',
          busy: true,
        ),
      SetupStage.awaitingConsent => _Consent(
          sizeBytes: state.totalBytes,
          onAccept: widget.provisioning.startDownload,
          onImport: widget.pickLocalModel == null ? null : _importFromStorage,
        ),
      SetupStage.downloading => _Progress(state: state),
      SetupStage.verifying => const _Centered(
          icon: Icons.verified_user,
          title: 'Conferindo o arquivo',
          message: 'Verificando a integridade do módulo de idiomas…',
          busy: true,
        ),
      SetupStage.ready => const _Centered(
          icon: Icons.check_circle,
          title: 'Tudo pronto',
          message: 'O aplicativo já funciona sem internet.',
        ),
      SetupStage.readyDegraded => const _Centered(
          icon: Icons.check_circle_outline,
          title: 'Pronto para atender',
          message: 'Seguindo sem a IA assistente. A orientação continua '
              'correta; baixamos o assistente quando houver Wi-Fi.',
        ),
      SetupStage.blocked => _Blocked(
          state: state,
          onRetry: widget.provisioning.startDownload,
          onImport: widget.pickLocalModel == null ? null : _importFromStorage,
          onContinueWithout: widget.provisioning.continueWithoutModel,
        ),
    };
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.message,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, semanticLabel: title),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (busy) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

/// Passo 1: valor + pedido explícito de permissão.
class _Consent extends StatelessWidget {
  const _Consent({
    required this.sizeBytes,
    required this.onAccept,
    this.onImport,
  });

  final int sizeBytes;
  final VoidCallback onAccept;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final gb = (sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_download, size: 96, semanticLabel: 'Download'),
        const SizedBox(height: 24),
        Text(
          'Preparar para uso offline',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(
          'Para funcionar 100% offline nos atendimentos, precisamos baixar o '
          'módulo de idiomas ($gb GB). Deseja iniciar agora?',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          // Alvo de toque ≥ 64 dp: o app é usado por quem tem pouca intimidade
          // com telas, às vezes de pé, no posto.
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: onAccept,
          child: const Text('Baixar agora'),
        ),
        if (onImport != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            style:
                OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            onPressed: onImport,
            child: const Text('Importar de um pendrive'),
          ),
        ],
      ],
    );
  }
}

/// Passo 2: barra ativa com porcentagem.
class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final SetupState state;

  @override
  Widget build(BuildContext context) {
    final percent = state.percent;
    final mb = (state.receivedBytes / (1024 * 1024)).round();
    final totalMb = (state.totalBytes / (1024 * 1024)).round();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          percent == null ? 'Baixando…' : 'Baixando… $percent%',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          minHeight: 16,
          // `null` = indeterminado. Melhor que fingir 0% quando o servidor não
          // informou o tamanho.
          value: percent == null ? null : percent / 100,
        ),
        const SizedBox(height: 12),
        Text('$mb MB de $totalMb MB', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        const Text(
          'Mantenha o aparelho conectado ao Wi-Fi. Se a conexão cair, '
          'continuamos de onde parou.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Trava: explica o impedimento e oferece as saídas.
class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.state,
    required this.onRetry,
    required this.onContinueWithout,
    this.onImport,
  });

  final SetupState state;
  final VoidCallback onRetry;
  final VoidCallback? onImport;

  /// Saída de emergência: abre a tela clínica em modo degradado.
  final VoidCallback onContinueWithout;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (state.blockReason) {
      SetupBlockReason.offline => (
          'Sem conexão',
          'Conecte o aparelho a uma rede Wi-Fi para preparar o aplicativo.'
        ),
      SetupBlockReason.meteredOnly => (
          'Somente dados móveis',
          'O download usa cerca de 800 MB. Conecte-se a um Wi-Fi, ou peça ao '
              'administrador para liberar o uso de dados móveis.'
        ),
      SetupBlockReason.insufficientDiskSpace => (
          'Espaço insuficiente',
          'Libere pelo menos 3 GB no aparelho e tente novamente.'
        ),
      SetupBlockReason.interrupted => (
          'Conexão interrompida',
          'O progresso foi salvo. Reconecte e continue de onde parou.'
        ),
      SetupBlockReason.integrityFailed => (
          'Arquivo inválido',
          'O arquivo baixado não passou na verificação de segurança e foi '
              'descartado. Tente novamente.'
        ),
      null => ('Não foi possível preparar', 'Tente novamente.'),
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline,
            size: 96, color: Colors.red, semanticLabel: 'Impedimento'),
        const SizedBox(height: 24),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        if (state.percent != null && state.receivedBytes > 0) ...[
          const SizedBox(height: 16),
          Text('${state.percent}% já baixado', textAlign: TextAlign.center),
        ],
        const SizedBox(height: 32),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: onRetry,
          child: const Text('Tentar novamente'),
        ),
        if (onImport != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            style:
                OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            onPressed: onImport,
            child: const Text('Importar de um pendrive'),
          ),
        ],
        const SizedBox(height: 24),
        // Deliberadamente menos proeminente que "tentar novamente": queremos
        // que o caminho bom seja o óbvio. Mas visível e sem jargão — quem
        // precisa dele está num posto sem rede, com alguém esperando.
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: onContinueWithout,
          child: const Text('Usar sem a IA assistente'),
        ),
        const Text(
          'A orientação continua correta e revisada. A IA apenas refina '
          'casos que não são de emergência.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
