import { defineConfig } from 'drizzle-kit';

/**
 * Gera o DDL do `content.db` a partir da MESMA fonte que alimenta o codegen,
 * eliminando um DDL escrito a mao no packer (fonte de verdade duplicada e o
 * debito que arquitetura.md 7 alerta).
 *
 * O SQL resultante (ddl/) e aplicado pelo packer ao construir cada pack.
 */
export default defineConfig({
  dialect: 'sqlite',
  schema: './src/content-schema.ts',
  out: './ddl',
});
