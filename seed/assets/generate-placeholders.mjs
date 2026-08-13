#!/usr/bin/env node
/**
 * Gera SVGs placeholder para todo asset declarado em `seed/000_assets.sql`.
 *
 * Le os caminhos do PROPRIO SQL, entao tabela e disco nao podem divergir. Se
 * alguem adicionar uma linha em `asset` e esquecer de rodar isto, o packer
 * falha na validacao referencial — o erro aparece antes da assinatura, nunca
 * no dispositivo.
 *
 * Estes NAO sao os icones do produto. O catalogo real vem do marco M1, apos
 * validacao de compreensao em campo com o publico-alvo (brainstorm.md M1).
 *
 * Uso: node seed/assets/generate-placeholders.mjs
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SEED_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const sql = readFileSync(join(SEED_DIR, '000_assets.sql'), 'utf8');

// Captura as tuplas (ref, kind, path, ...) dos INSERTs.
const rows = [...sql.matchAll(/\('([^']+)',\s*'(icon|image)',\s*'([^']+)'/g)].map((m) => ({
  ref: m[1],
  kind: m[2],
  path: m[3],
}));

if (rows.length === 0) {
  console.error('Nenhum asset encontrado em 000_assets.sql — abortando.');
  process.exit(1);
}

/** Cor derivada do ref: placeholders distinguiveis entre si, sem significado. */
function hueFor(ref) {
  let h = 0;
  for (const ch of ref) h = (h * 31 + ch.charCodeAt(0)) % 360;
  return h;
}

/** Rotulo curto para o placeholder ficar legivel na inspecao visual. */
function labelFor(ref) {
  return ref.split('.').pop().slice(0, 6);
}

let written = 0;
for (const { ref, kind, path } of rows) {
  const size = kind === 'image' ? 128 : 64;
  const hue = hueFor(ref);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" role="img" aria-label="${ref}">
  <title>PLACEHOLDER ${ref}</title>
  <rect width="${size}" height="${size}" rx="${size / 6}" fill="hsl(${hue} 45% 92%)" stroke="hsl(${hue} 45% 45%)" stroke-width="2"/>
  <text x="50%" y="54%" text-anchor="middle" dominant-baseline="middle" font-family="sans-serif" font-size="${size / 5}" fill="hsl(${hue} 45% 30%)">${labelFor(ref)}</text>
</svg>
`;
  const target = join(SEED_DIR, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, svg, 'utf8');
  written += 1;
}

console.log(`${written} placeholders gerados em seed/assets/ (nao sao os icones do produto)`);
