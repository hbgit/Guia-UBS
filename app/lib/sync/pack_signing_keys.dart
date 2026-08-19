/// Chaves públicas Ed25519 que este binário aceita como emissoras de conteúdo.
///
/// ===========================================================================
/// ESTA É A RAIZ DE CONFIANÇA DO CONTEÚDO CLÍNICO
/// ===========================================================================
///
/// Quem controla a chave privada correspondente pode mandar qualquer orientação
/// para toda a frota — inclusive "isso não é emergência, fique em casa". É o
/// SPOF R4 do [PRD.md §4.2]. A privada vive em cofre offline/HSM e só o CI
/// assina, com aprovação manual ([contract/keys/README.md]).
///
/// ## Rotação sem release
///
/// O binário aceita **duas** chaves ao mesmo tempo. Para rotar: publique packs
/// assinados com `k2` enquanto `k1` ainda é aceita, e só aposente `k1` numa
/// versão futura do app. O `keyId` do manifest diz qual conferir. Sem esse
/// intervalo de sobreposição, rotar a chave deixaria offline todo aparelho que
/// ainda não atualizou o APK — que é exatamente a população que este projeto
/// atende.
///
/// ## Como as chaves entram aqui
///
/// Valores são hex dos **32 bytes crus** da chave pública, não PEM: o app não
/// tem parser ASN.1 e não precisa de um. Para extrair de um `.pub`:
///
/// ```sh
/// openssl pkey -pubin -in pack-signing-k1.pub -outform DER | tail -c 32 | xxd -p -c 32
/// ```
///
/// Em release, a chave real entra por `--dart-define` — o valor abaixo é a
/// chave de DESENVOLVIMENTO versionada em `contract/keys/`, e assinar com ela
/// é trivial para qualquer um que clone o repositório.
library;

/// Chave de desenvolvimento (`contract/keys/pack-signing-k1.pub`).
///
/// Serve para o packer local e para os testes. **Não** é segredo e **não**
/// pode ser a chave de um APK distribuído.
const String devPackSigningKeyK1 =
    'bbfd5b2b69d27c539a4d29a4167319508bbf36130590d22289676a0e7e237dfa';

const String _k1 = String.fromEnvironment(
  'PACK_SIGNING_KEY_K1',
  defaultValue: devPackSigningKeyK1,
);

/// Segunda posição, vazia até a primeira rotação. Uma entrada vazia é ignorada
/// pelo verificador — não é uma chave que aceita qualquer assinatura.
const String _k2 = String.fromEnvironment('PACK_SIGNING_KEY_K2');

/// Chaves aceitas, indexadas pelo `keyId` do manifest.
const Map<String, String> packSigningKeys = <String, String>{
  'k1': _k1,
  'k2': _k2,
};
