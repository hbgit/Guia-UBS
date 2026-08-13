# Chaves de assinatura de pacotes

Somente **chaves públicas** (`*.pub`) são versionadas aqui. O `.gitignore` bloqueia
`*.pem` — a chave privada é o SPOF mais crítico do sistema ([PRD.md §4.2](../../docs/PRD.md),
risco R4): comprometê-la permite distribuir orientação clínica falsa para toda a frota.

## Regras

- **Produção:** chave privada em cofre offline/HSM. Assinatura acontece **apenas no CI**,
  em job com aprovação manual. Nenhuma máquina de desenvolvimento vê a chave de produção.
- **Desenvolvimento:** gere um par descartável, nunca reutilizado em produção.
- **Rotação sem release:** o app embarca **duas** chaves públicas (`k1` e `k2`). Para rotar,
  publique packs assinados com `k2` enquanto `k1` ainda é aceita; depois aposente `k1`
  numa versão futura do binário. O `keyId` do manifest indica qual validar.

## Gerar par de desenvolvimento

```bash
openssl genpkey -algorithm ed25519 -out dev-k1.pem
openssl pkey -in dev-k1.pem -pubout -out pack-signing-k1.pub
```

## Verificação no device

O app valida a assinatura do manifest canônico ([contract/src/manifest.ts](../src/manifest.ts))
antes de qualquer download de pack, e o SHA-256 de cada artefato antes do swap atômico.
O servidor de conteúdo e seus espelhos são tratados como infraestrutura não-confiável.
