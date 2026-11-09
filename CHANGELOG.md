# Changelog do app

Versões do aplicativo Android, no formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
O versionamento é SemVer, e o `versionCode` é `MAJOR*10000 + MINOR*100 + PATCH`
([ADR-009](spec/stack.md)). A versão do **pack de conteúdo** é outra coisa e
segue em `contract/CHANGELOG.md`.

Cada release do GitHub copia daqui a seção da própria versão. O workflow
(`.github/workflows/app-release.yml`) reprova a tag cuja seção não existe.

## [Não lançado]

## [0.1.0]

Primeira versão para **teste interno** (dogfooding), antes do lançamento ([ADR-010](spec/stack.md)).

### Adicionado
- Módulos educativos sobre o SUS e a Atenção Primária, em português e espanhol,
  com ícones e áudio.
- Orientação de onde procurar atendimento como apoio, com gate determinístico de
  sinais de alerta e assistente local opcional.
- Selo de procedência: "regras de segurança do app" ou "assistente virtual".
- Aviso de não afiliação: o app não é serviço de saúde e não fala por UBS, SUS,
  Secretaria ou Ministério.
- Funciona sem internet. Atualização de conteúdo assinada (Ed25519) quando houver
  rede.
- Dois APKs: `arm64` (com o assistente) e `arm` (aparelhos 32 bits, sem o
  assistente).
