# Plano de controle — imagem de producao.
#
# Base **glibc** (`bookworm-slim`), nao Alpine: `@node-rs/argon2` distribui
# binario pre-compilado para os dois, mas Alpine/musl e onde a ausencia de um
# prebuild aparece como falha de compilacao no meio do `npm ci`. Aqui o custo de
# uns megabytes a mais compra um build que nao depende de toolchain nenhuma.
#
# Multi-stage por dois motivos, e o primeiro nao e o que este comentario dizia
# antes: o estagio `web` compila o bundle do navegador SEM que o resultado dependa
# da maquina de quem constroi, e o `deps` isola a resolucao do `npm ci`.
#
# O que ele NAO faz e enxugar devDependencies. `production` copia `node_modules`
# inteiro do `deps`, entao `tsx`, `drizzle-kit`, `vite` e `vitest` viajam junto —
# `tsx` obrigatoriamente, porque o `CMD` o invoca. Enxugar de verdade exigiria
# mover `tsx` para `dependencies` e reinstalar com `--omit=dev` num estagio
# proprio; e trabalho de outro PR, e ate la o comentario diz a verdade.

FROM node:22-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
COPY contract/package.json contract/
COPY cms/package.json cms/
# `cms/web` esta em `workspaces` na raiz, e o npm exige o package.json de CADA
# workspace declarado. Sem esta linha o `npm ci` abaixo falha — dentro do Docker,
# com uma mensagem sobre workspace ausente, onde ninguem esta olhando.
COPY cms/web/package.json cms/web/
COPY packer/package.json packer/
RUN npm ci

# Estagio de build da interface. `arquitetura.md` §3.2 ja prescrevia um estagio de
# build para este Dockerfile — nao e desvio da regra de nao transpilar o servidor,
# que continua valendo: o TypeScript de `cms/src` roda como esta escrito. O que se
# constroi aqui e o bundle do navegador, que nao tem como nao ser construido.
FROM deps AS web
COPY contract/ ./contract/
COPY cms/ ./cms/
RUN npm --workspace @guia-ubs/cms-web run build

# Base comum dos dois alvos: dependencias e o contrato, que cms e packer importam.
FROM node:22-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY contract/ ./contract/

# Job de empacotamento (servico `packer` do compose, `target: packer`). Leva so o
# que o worker le — `packer/test/imagem-docker.test.ts` confere estes COPY contra
# os caminhos usados. NAO leva `cms/`: o codigo que atende HTTP fica fora da
# imagem que le a chave. A chave em si e montada como segredo, nunca copiada.
FROM runtime AS packer
COPY packer/package.json packer/
COPY packer/src/ ./packer/src/
# O worker ainda le o binario de asset daqui, nao do banco (lacuna da §5.20).
COPY seed/assets/ ./seed/assets/
# Registro PUBLICO de atestados: trocar o arquivo exige rebuild e redeploy (§5.17).
COPY seed/golden/atestados.yaml ./seed/golden/
# `packer/out` fica fora do contexto (.dockerignore) e /app e do root: sem isto o
# build do pack morre com EACCES rodando como `node`.
RUN mkdir -p packer/out && chown node:node packer/out
USER node
CMD ["node", "--import", "tsx", "packer/src/worker.ts", "--interval", "60"]

# CMS. Fica por ULTIMO: `docker build` sem `--target` entrega este estagio.
FROM runtime AS production
COPY cms/ ./cms/
# better-auth e companhia ficam ANINHADOS em cms/node_modules (o npm nao os ica),
# e o `.dockerignore` tira todo node_modules do contexto: sem esta linha o CMS
# morre no boot com ERR_MODULE_NOT_FOUND 'better-auth'.
COPY --from=deps /app/cms/node_modules ./cms/node_modules
# DEPOIS do `COPY cms/` de proposito: um `cms/web/dist` velho na maquina de quem
# constroi nunca vence o que o estagio `web` acabou de compilar. (O `.dockerignore`
# ja exclui `**/dist` do contexto; esta ordem e a segunda barreira, para o caso de
# alguem afrouxar aquele arquivo.)
COPY --from=web /app/cms/web/dist ./cms/web/dist

# Nao roda como root: um comprometimento do processo nao vira comprometimento
# do container.
USER node

EXPOSE 8787

# `tsx` executa o TypeScript direto. E deliberado nao ter passo de transpilacao:
# o que roda em producao e o mesmo arquivo que se le no repositorio, sem source
# map no meio para conferir na hora de investigar um incidente.
CMD ["node", "--import", "tsx", "cms/src/index.ts"]
