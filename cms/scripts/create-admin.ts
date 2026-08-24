/**
 * Cria o primeiro operador — o unico caminho que nao exige um operador ja
 * existente.
 *
 * Nao ha auto-cadastro no sistema (`disableSignUp: true`), entao sem este script
 * o banco recem-migrado seria inacessivel para sempre. Ele exige acesso ao banco,
 * que e a credencial: quem consegue rodar isto ja teria como escrever a linha na
 * mao.
 *
 * Uso:
 *   npm run cms:create-admin -- --email admin@exemplo.invalid --name "Nome"
 *   npm run cms:create-admin -- --email … --name … --role editor --password …
 *
 * Sem `--password`, uma senha forte e sorteada e impressa UMA vez. E o padrao
 * de proposito: senha passada em linha de comando fica no historico do shell e
 * na lista de processos da maquina.
 */
import { randomBytes } from 'node:crypto';
import { parseArgs } from 'node:util';

import { ADMIN_ROLES } from '../src/db/schema/auth.js';
import { createDatabaseClient } from '../src/db/client.js';
import { loadEnv } from '../src/env.js';
import { isAdminRole } from '../src/auth/permissions.js';
import { createOperator } from '../src/services/operators.js';

const { values } = parseArgs({
  options: {
    email: { type: 'string' },
    name: { type: 'string' },
    role: { type: 'string', default: 'admin' },
    password: { type: 'string' },
  },
});

if (!values.email || !values.name) {
  console.error('uso: --email <e-mail> --name <nome> [--role admin|editor|clinical_reviewer]');
  process.exit(2);
}
if (!isAdminRole(values.role)) {
  console.error(`--role precisa ser um de: ${ADMIN_ROLES.join(', ')}`);
  process.exit(2);
}

/** 24 bytes em base64url: entropia muito acima do minimo de 12 caracteres. */
const senha = values.password ?? randomBytes(24).toString('base64url');
const sorteada = !values.password;

const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);
try {
  const criado = await createOperator(
    client,
    env.hashSalt,
    { email: values.email, name: values.name, role: values.role, password: senha },
    // Sem ator: nao havia operador para autorizar o primeiro operador. A trilha
    // registra a criacao com ator nulo, que e a verdade do bootstrap.
    null,
  );
  console.log(`  criado  ${criado.email}  papel=${criado.role}  id=${criado.id}`);
  if (sorteada) {
    console.log(`  senha   ${senha}`);
    console.log('          (mostrada uma unica vez — guarde agora)');
  }
  console.log('\n  O 2FA ainda NAO esta ativo. Enquanto nao estiver, esta conta nao');
  console.log('  alcanca rota protegida nenhuma: ative em /api/auth/two-factor/enable.');
} finally {
  client.close();
}
