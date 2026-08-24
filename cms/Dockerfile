# Plano de controle — imagem de producao.
#
# Base **glibc** (`bookworm-slim`), nao Alpine: `@node-rs/argon2` distribui
# binario pre-compilado para os dois, mas Alpine/musl e onde a ausencia de um
# prebuild aparece como falha de compilacao no meio do `npm ci`. Aqui o custo de
# uns megabytes a mais compra um build que nao depende de toolchain nenhuma.
#
# Multi-stage para que a imagem final nao carregue devDependencies: `drizzle-kit`
# e `tsx` existem para gerar migracao e rodar teste, e nao tem por que estar numa
# imagem exposta a rede.

FROM node:22-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
COPY contract/package.json contract/
COPY cms/package.json cms/
COPY packer/package.json packer/
RUN npm ci

FROM node:22-bookworm-slim AS production
WORKDIR /app
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY contract/ ./contract/
COPY cms/ ./cms/

# Nao roda como root: um comprometimento do processo nao vira comprometimento
# do container.
USER node

EXPOSE 8787

# `tsx` executa o TypeScript direto. E deliberado nao ter passo de transpilacao:
# o que roda em producao e o mesmo arquivo que se le no repositorio, sem source
# map no meio para conferir na hora de investigar um incidente.
CMD ["node", "--import", "tsx", "cms/src/index.ts"]
