# Gerar a chave Ed25519 de produção (mantenedor A)

Este roteiro é para o **mantenedor A**, que fica com a custódia da chave de assinatura dos packs de conteúdo. O resultado é:

- a chave **privada**, cifrada com senha, guardada em **duas** mídias offline (uma com o mantenedor A e outra com o mantenedor B);
- a chave **pública** em hex (64 caracteres), a única coisa que sai daqui. Ela vai para o `PACK_SIGNING_KEY_K1` do `app/config/defines.release.json` (Task 10 do plano B).

O porquê está em [`spec/stack.md`](../../spec/stack.md): Revisão 2026-11-12 do ADR-001 (assinatura provisória por dois mantenedores) e ADR-007 (custódia dupla). O uso da chave depois de gerada está em [`docs/operacao.md`](../operacao.md) §2.7b.

## Por que tanto cuidado

Esta chave é a **raiz de confiança do conteúdo clínico**. Quem tiver a privada consegue mandar a todos os aparelhos qualquer orientação, inclusive "isso não é emergência, fique em casa". Isso não tem volta rápida: a pública fica gravada no APK, e trocá-la exige uma versão nova do app (rotação para `k2`) e esperar que os aparelhos atualizem.

Por isso a chave:

- **nasce numa máquina sem rede** e nunca toca disco persistente sem estar cifrada;
- **nunca vai para CI**, para o repositório, para a VPS, para e-mail, chat ou nuvem;
- **nunca é lida, gerada ou guardada por um agente de IA**. O agente recebe só a pública.

## O que você precisa

- [ ] Uma máquina **sem rede**. O ideal é um pendrive com um Linux *live* (Fedora, Debian ou Tails) iniciado com o cabo desconectado e o Wi-Fi desligado. Serve um notebook com o rádio desligado, mas o *live* não deixa rastro.
- [ ] OpenSSL 3 (`openssl version`). As distribuições *live* atuais já trazem.
- [ ] **Duas** mídias para a cópia cifrada, por exemplo dois pendrives: um fica com o mantenedor A, o outro com o mantenedor B.
- [ ] Uma **senha forte** para a chave: frase de 6 ou mais palavras aleatórias. Os dois mantenedores guardam a senha, cada um no próprio gerenciador de senhas. Ela nunca vai junto da mídia.
- [ ] O mantenedor B presente ou disponível para o passo 6.

## 1. Preparar o ambiente

Com a máquina já sem rede:

```sh
nmcli networking off 2>/dev/null; ip -brief link   # nenhuma interface além de lo deve estar UP
swapon --show                                      # deve sair vazio; se houver swap: sudo swapoff -a
umask 077
cd /dev/shm                                        # tmpfs: some ao desligar
```

O swap desligado importa porque uma página do `/dev/shm` pode ser gravada no swap, ou seja, em disco.

## 2. Gerar o par, já cifrado

```sh
openssl genpkey -algorithm ed25519 -aes-256-cbc -out pack-signing-k1-prod.enc.pem
```

O OpenSSL pede a senha duas vezes. O arquivo começa com `-----BEGIN ENCRYPTED PRIVATE KEY-----`; confira com `head -1 pack-signing-k1-prod.enc.pem`. Se aparecer `BEGIN PRIVATE KEY` sem `ENCRYPTED`, apague o arquivo e refaça: faltou o `-aes-256-cbc`.

**Não** gere a chave sem cifra "para cifrar depois".

## 3. Extrair a pública

```sh
openssl pkey -in pack-signing-k1-prod.enc.pem -pubout -out pack-signing-k1-prod.pub
openssl pkey -pubin -in pack-signing-k1-prod.pub -outform DER | tail -c 32 | xxd -p -c 32 | tee pack-signing-k1-prod.hex
```

O primeiro comando pede a senha. O segundo imprime **uma linha com 64 caracteres hexadecimais**: é o valor que vai para o app.

Duas conferências:

```sh
wc -c < pack-signing-k1-prod.hex        # 65 (64 caracteres + quebra de linha)
grep -c bbfd5b2b pack-signing-k1-prod.hex   # 0: não é a chave de DESENVOLVIMENTO
```

## 4. Provar que a senha e a chave funcionam

Assine e verifique uma mensagem qualquer antes de guardar. Uma senha digitada errado duas vezes iguais só seria descoberta no primeiro pack.

```sh
printf 'teste' > m
openssl pkeyutl -sign -rawin -inkey pack-signing-k1-prod.enc.pem -in m -out m.sig
openssl pkeyutl -verify -rawin -pubin -inkey pack-signing-k1-prod.pub -in m -sigfile m.sig
# esperado: Signature Verified Successfully
```

## 5. Guardar nas duas mídias

Copie para **cada** mídia o arquivo cifrado e a pública. O `.pub` e o `.hex` não são segredo, mas ficam junto para conferência.

```sh
for m in /run/media/$USER/MIDIA-A /run/media/$USER/MIDIA-B; do
  cp pack-signing-k1-prod.enc.pem pack-signing-k1-prod.pub pack-signing-k1-prod.hex "$m"/
done
sha256sum pack-signing-k1-prod.enc.pem /run/media/$USER/MIDIA-*/pack-signing-k1-prod.enc.pem
# os três hashes iguais
sync
```

Troque `MIDIA-A`/`MIDIA-B` pelos nomes reais das montagens. O hex que você vai entregar no passo 7 fica no `.hex` da mídia A. Depois:

```sh
rm -f /dev/shm/pack-signing-k1-prod.* /dev/shm/m /dev/shm/m.sig
```

Desligue a máquina. Rotule as mídias (por exemplo "Guia UBS — k1 — 2026-11"), sem escrever a senha nelas. A mídia do mantenedor B vai para ele em mãos.

## 6. Conferência independente pelo mantenedor B

O mantenedor B, também numa máquina sem rede, deriva a pública **da cópia dele**:

```sh
openssl pkey -in pack-signing-k1-prod.enc.pem -pubout -outform DER | tail -c 32 | xxd -p -c 32
```

O hex tem que ser **idêntico** ao do passo 3. Isso prova três coisas: a mídia de B está íntegra, B sabe a senha e o hex que chega ao app é o da chave guardada.

## 7. Entregar só a pública

Cole aqui, na conversa com o agente, **somente** a linha de 64 caracteres. A pública não é segredo, mas a **integridade** dela importa: um hex trocado no caminho daria a frota a quem tem a outra privada. Por isso:

- o mantenedor A cola o hex na conversa;
- o mantenedor B confirma o **mesmo** hex por outro canal, por exemplo num comentário na PR da Task 10;
- o agente faz a Task 10: grava o hex como `PACK_SIGNING_KEY_K1` em `app/config/defines.release.json`, com `PACK_MANIFEST_URL=https://guiasaude.conteudo.prismrr.com.br/content-packs/0000000/manifest.json`, e roda a guarda `tool/model_url_check.dart --mode release`.

**Nunca cole** o conteúdo do `.enc.pem`, a senha ou a saída de um `openssl pkey` sem `-pubout`.

## Depois: usar a chave para assinar

O "comando do cofre" do runbook (`docs/operacao.md` §2.7b) passa a ser a decifração da mídia, entregue ao packer por um pipe:

```sh
openssl pkey -in /run/media/$USER/MIDIA-A/pack-signing-k1-prod.enc.pem \
  | PACK_SIGNING_KEY_PATH=/dev/stdin npm run pack:key
# pede a senha; imprime o mesmo hex do passo 3
```

A privada decifrada só existe no pipe: não vai para disco. Use `| … /dev/stdin`, e **não** `<(…)` nem `3< <(…)`. O `npm run` não repassa o fd 3, e no zsh o `<(…)` vira `/proc/self/fd/11`, que o processo filho do npm não consegue abrir (EACCES). Há teste disso em `packer/test/cli.test.ts`.

## Checklist

- [ ] Máquina sem rede, swap desligado, trabalho em `/dev/shm`
- [ ] Chave gerada **já cifrada** (`ENCRYPTED PRIVATE KEY`)
- [ ] Hex de 64 caracteres, diferente de `bbfd5b2b…`
- [ ] Assinatura de teste verificada
- [ ] Duas mídias com o mesmo sha256, rotuladas, sem a senha junto
- [ ] Senha guardada pelos dois mantenedores
- [ ] Arquivos apagados do `/dev/shm` e máquina desligada
- [ ] Mantenedor B derivou o mesmo hex da cópia dele
- [ ] Hex colado na conversa e confirmado por B em outro canal
