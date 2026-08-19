# Fixtures do sync (FSM-B)

Artefatos **assinados pelo packer real**, com a chave de desenvolvimento
`contract/keys/dev-k1.pem`. Não são JSON escritos à mão: é justamente por serem
saída do assinador em Node que eles provam que a serialização canônica em Dart
(`app/lib/sync/pack_manifest.dart`) bate byte a byte com a de
`contract/src/manifest.ts`.

Se essas duas divergirem em um único byte, toda assinatura legítima passa a
parecer forjada e a frota inteira para de receber conteúdo — sem nenhuma
mensagem de erro que explique por quê. Por isso o teste que os consome
(`test/sync/manifest_verifier_test.dart`) não pode ser substituído por um que
assine em Dart.

## Regerar

`SOURCE_DATE_EPOCH` é obrigatório: sem ele o packer carimba o relógio de parede
em `pack_meta.built_at` e em `publishedAt`, e o pack sai com hash diferente a
cada build — o que quebraria as constantes dos testes e, em produção, obrigaria
a frota inteira a re-baixar o pack por uma linha de metadado.

```sh
export SOURCE_DATE_EPOCH=1787097600           # 2026-08-19T00:00:00Z
export PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem

PACK_VERSION=1 npm run pack:build
cp packer/out/manifest.json app/test/fixtures/sync/manifest-v1.json
cp packer/out/content.db    app/test/fixtures/sync/pack-v1.db

PACK_VERSION=2 npm run pack:build
cp packer/out/manifest.json app/test/fixtures/sync/manifest-v2.json
cp packer/out/content.db    app/test/fixtures/sync/pack-v2.db
```

Se o conteúdo de `seed/` mudar, os hashes mudam junto. Os testes referenciam
alguns por constante — `packV1Url`, `packV2Url` e `packV1Hash` em
`test/sync/sync_service_test.dart`, e o hash esperado em
`test/sync/manifest_verifier_test.dart` — e precisam acompanhar.

O `.gitignore` da raiz ignora `*.db`; há uma exceção explícita para este
diretório.
