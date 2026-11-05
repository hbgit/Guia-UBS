Para o Guia-UBS, a configuração é a de um **subdomínio personalizado** apontando para o site de projeto do repositório `hbgit/Guia-UBS` (onde estão a política de privacidade e os termos). Hoje ele responde em `hbgit.github.io/Guia-UBS`; a ideia é que passe a responder em `guiasaude.prismrr.com.br`.

## 1. Verifique o domínio na sua conta do GitHub (recomendado)

Esse passo impede que outra conta do GitHub "sequestre" seu subdomínio caso o Pages fique desativado algum dia.

1. Acesse **Settings da sua conta (não do repositório) → Pages → Add a domain**.
2. Informe `prismrr.com.br`. Verificar o domínio raiz cobre todos os subdomínios.
3. O GitHub vai mostrar um registro TXT parecido com este:

| Tipo | Nome | Valor |
|---|---|---|
| TXT | `_github-pages-challenge-hbgit` | (código gerado pelo GitHub) |

4. Crie esse registro no DNS, espere propagar e clique em **Verify**.

## 2. Crie o registro CNAME no DNS

No painel onde o DNS de `prismrr.com.br` é gerenciado (Registro.br em modo avançado, Cloudflare, ou o provedor da VPS), crie:

| Tipo | Nome | Valor | TTL |
|---|---|---|---|
| CNAME | `guiasaude` | `hbgit.github.io.` | 3600 (ou o padrão) |

Alguns pontos importantes:

- O valor é **apenas** `hbgit.github.io`, sem `/Guia-UBS`. O GitHub identifica qual repositório atender pelo domínio configurado no passo 3.
- Não use registros A nem AAAA para um subdomínio. Os IPs do GitHub (185.199.108–111.153) só são necessários para o domínio raiz (apex).
- Se usar Cloudflare, deixe o registro como **DNS only** (nuvem cinza) pelo menos até o certificado ser emitido. Com o proxy ativo, a emissão do HTTPS pelo GitHub costuma falhar.
- Se o DNS do Registro.br estiver no modo básico, ele não aceita CNAME. Nesse caso, ative o modo avançado ou delegue o DNS para outro provedor.

## 3. Configure o domínio no repositório

1. Em `hbgit/Guia-UBS`, vá em **Settings → Pages → Custom domain**, digite `guiasaude.prismrr.com.br` e clique em **Save**. O GitHub faz um DNS check.
2. A partir daqui, depende de como o Pages é publicado:
   - **Deploy from a branch** (ex.: `gh-pages` ou `/docs`): o GitHub cria um arquivo `CNAME` nessa branch/pasta com o domínio. Não apague esse arquivo. Se algum script regerar a pasta, inclua o `CNAME` no build.
   - **GitHub Actions**: o arquivo `CNAME` é ignorado. Vale apenas o que está configurado na tela de Settings.
3. Quando o certificado estiver pronto, marque **Enforce HTTPS**. O GitHub emite o certificado via Let's Encrypt. Normalmente isso leva minutos, mas pode chegar a 24 h.

## 4. Valide

```bash
dig guiasaude.prismrr.com.br +noall +answer
# esperado: guiasaude.prismrr.com.br. CNAME hbgit.github.io.

dig TXT _github-pages-challenge-hbgit.prismrr.com.br +short

curl -I https://guiasaude.prismrr.com.br
# esperado: HTTP/2 200 e certificado válido
```

## Cuidados específicos do Guia-UBS

- **Google Play**: atualize a URL da política de privacidade no Play Console e dentro do app (tela "Sobre"/termos) para `https://guiasaude.prismrr.com.br/...`. O endereço antigo `hbgit.github.io/Guia-UBS` passa a redirecionar automaticamente, mas o ideal é que a loja aponte para o domínio definitivo.
- **Registro CAA**: se `prismrr.com.br` tiver registro CAA, ele precisa autorizar `letsencrypt.org`. Sem isso, o HTTPS não é emitido.
- **Separação da VPS**: o subdomínio do CMS (ex.: `cms.prismrr.com.br`) fica com registro A apontando para o IP da VPS, totalmente independente do `guiasaude`. Isso é coerente com a decisão de manter os documentos legais no Pages.
- **Sem wildcard**: evite `*.prismrr.com.br` apontando para o GitHub, porque isso abre margem para takeover de subdomínios.

---

# Note

O valor é `hbgit.github.io.`. O ponto final que coloquei não faz parte do endereço: é a notação de **FQDN** (nome de domínio totalmente qualificado), que indica que o nome termina na raiz do DNS. Se você deve digitar o ponto ou não depende de onde vai configurar.

- **Painéis web** (Cloudflare, Registro.br, Hostinger, Locaweb etc.): normalmente basta digitar `hbgit.github.io`, sem o ponto. O painel trata o valor como absoluto. Alguns aceitam o ponto, outros removem sozinhos.
- **Arquivo de zona BIND** (por exemplo, se o DNS estiver rodando na sua própria VPS): o ponto final é **obrigatório**. Sem ele, o BIND concatena o nome da zona e o registro passa a apontar para `hbgit.github.io.prismrr.com.br`, que não existe.

Em qualquer caso, depois de salvar, confirme com:

```bash
dig guiasaude.prismrr.com.br CNAME +short
```

O retorno deve ser `hbgit.github.io.`. O `dig` sempre mostra o ponto no final, e isso é normal. Se aparecer `hbgit.github.io.prismrr.com.br.`, o painel concatenou a zona e você precisa ajustar o valor.

# ISSUE with Enforce HTTPS

Quando a opção **Enforce HTTPS** aparece desabilitada, é porque o GitHub ainda não tem um certificado válido para o domínio. Logo abaixo do campo *Custom domain* costuma aparecer uma mensagem que mostra em qual fase está o problema.

**1. Certificado ainda sendo emitido.** Se a mensagem for parecida com *"Not yet available for your site because the certificate has not finished being issued"*, não há nada errado: é só esperar. Costuma levar de alguns minutos a uma hora, mas pode chegar a 24 h.

**2. DNS check falhou ou ainda está pendente.** Mensagens como *"Domain's DNS record could not be retrieved"* ou *"improperly configured"* indicam que o GitHub ainda não enxerga o CNAME. Rode este comando:

```bash
dig guiasaude.prismrr.com.br +short
```

O retorno precisa ser `hbgit.github.io.` seguido de IPs da faixa `185.199.108–111.153`. Se vier vazio, o registro ainda não propagou. Se vier `hbgit.github.io.prismrr.com.br.`, é o problema do ponto final que comentamos antes.

**3. Cloudflare com proxy ativo.** Se a nuvem estiver laranja, o GitHub enxerga IPs da Cloudflare e não consegue validar o domínio. Mude o registro para **DNS only** (nuvem cinza).

**4. Registros conflitantes.** Não pode existir nenhum outro registro (A, AAAA, TXT, MX) com o nome `guiasaude` além do CNAME. Alguns painéis criam registros desse tipo automaticamente.

**5. Registro CAA bloqueando o Let's Encrypt.** Verifique com:

```bash
dig prismrr.com.br CAA +short
```

Se aparecer algum resultado e nenhum deles contiver `letsencrypt.org`, adicione `0 issue "letsencrypt.org"`.

**6. Emissão travada.** Se o DNS já estiver correto e mesmo assim nada mudar depois de algumas horas, force uma nova tentativa: em **Settings → Pages**, clique em **Remove** no domínio personalizado, espere um minuto, digite `guiasaude.prismrr.com.br` de novo e salve. Isso dispara uma nova solicitação de certificado e resolve a maioria dos casos travados.

---

# ISSUE com pages no github

O CNAME está correto: `guiasaude.prismrr.com.br` aponta para `hbgit.github.io` e resolve nos quatro IPs do GitHub. O DNS do subdomínio está resolvido. O que você está vendo são **dois problemas independentes**.

## Problema 1: Enforce HTTPS desabilitado

A verificação do domínio na conta **não** é pré-requisito para o HTTPS. Com o DNS já correto, o mais provável é que a emissão do certificado tenha travado, algo comum quando o domínio é salvo no repositório antes de o DNS propagar. Para resolver:

1. Em `hbgit/Guia-UBS` → **Settings → Pages**, clique em **Remove** ao lado do domínio personalizado.
2. Espere cerca de 1 minuto.
3. Digite `guiasaude.prismrr.com.br` novamente e clique em **Save**.
4. Aguarde o DNS check ficar verde e o certificado ser emitido. Normalmente leva de 15 minutos a 1 hora. Depois disso, a caixa **Enforce HTTPS** fica habilitada.

## Problema 2: TXT de verificação não encontrado

O erro mais comum no Registro.br é o **nome** do registro. O campo de nome no editor do Registro.br é relativo à zona: o Registro.br completa com `.prismrr.com.br` automaticamente. Por isso, a entrada deve ficar assim:

| Tipo | Nome (o que você digita) | Valor |
|---|---|---|
| TXT | `_github-pages-challenge-hbgit` | código exibido pelo GitHub, sem espaços extras |

Erros que fazem a verificação falhar:

- **Digitar o nome completo** (`_github-pages-challenge-hbgit.prismrr.com.br`). O registro vira `...prismrr.com.br.prismrr.com.br`.
- **Deixar o nome vazio**. O TXT fica no domínio raiz e o GitHub não o encontra.
- **Copiar o código com aspas ou espaços** a mais.
- **Não salvar a zona**. No Registro.br, depois de adicionar o registro é preciso clicar em **Salvar alterações**. A publicação da zona também pode levar alguns minutos.

Para checar se o registro foi publicado:

```bash
dig TXT _github-pages-challenge-hbgit.prismrr.com.br +short
```

O retorno deve ser o código entre aspas. Se vier vazio, consulte direto o servidor autoritativo para descartar cache:

```bash
dig NS prismrr.com.br +short
dig TXT _github-pages-challenge-hbgit.prismrr.com.br @<primeiro servidor listado acima> +short
```

Se o servidor autoritativo também retornar vazio, o registro está com o nome errado ou não foi salvo. Se ele retornar o código, é só aguardar a propagação e clicar em **Verify** de novo no GitHub.

