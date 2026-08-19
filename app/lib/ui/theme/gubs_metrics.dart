/// Medidas que a acessibilidade exige (RNF-06), não que o gosto sugere.
///
/// Estão em constantes nomeadas porque cada uma tem um teste que a verifica no
/// widget renderizado. Um número solto no meio de um `Padding` não tem como ser
/// verificado, e é assim que "alvo de 64 dp" vira "48 dp em três telas".
library;

/// Menor lado de qualquer alvo tocável.
///
/// Material manda 48 dp; aqui são **64**. A diferença é o público: mãos
/// calejadas de trabalho rural, presbiopia sem óculos, e uso em pé segurando
/// outra coisa. O número veio da espec, não de um design system.
const double minTouchTarget = 64;

/// Máximo de elementos acionáveis por tela.
///
/// Não é regra de estética: acima disso a tela exige leitura para ser
/// escaneada, e o público-alvo é definido por não conseguir fazer essa leitura.
const int maxElementsPerScreen = 8;

/// Profundidade máxima de navegação a partir da raiz (CAP-02).
const int maxNavigationDepth = 4;

/// Espaçamento base. Múltiplos de 8 mantêm o ritmo vertical previsível.
const double spacing = 8;

/// Raio dos cartões e botões, seguindo o protótipo `docs/design.html`.
const double radiusCard = 20;
const double radiusButton = 16;

/// Duração máxima entre tocar a bandeira e a UI inteira estar no outro idioma
/// (critério de aceitação da RF-01).
const Duration localeSwitchBudget = Duration(milliseconds: 200);

/// Tempo de inatividade que devolve a FSM-A ao repouso.
const Duration sessionIdleTimeout = Duration(seconds: 120);
