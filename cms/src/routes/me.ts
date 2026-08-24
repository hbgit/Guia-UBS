/**
 * `GET /api/me` — quem sou eu e o que posso.
 *
 * Existe para o SPA saber quais telas oferecer sem adivinhar pelo papel: o
 * cliente recebe a lista de PERMISSOES resolvida, nao a regra. Assim mudar a
 * matriz em `auth/permissions.ts` nao exige mexer no front, e o front nunca tem
 * uma segunda copia da regra de acesso — que divergiria.
 *
 * O servidor continua sendo quem decide: esta lista e para desenhar a interface,
 * nunca para autorizar. Toda rota tem o seu proprio `requirePermission`.
 */
import { Hono } from 'hono';

import type { AuthVariables } from '../auth/middleware.js';
import { ROLE_PERMISSIONS, isAdminRole } from '../auth/permissions.js';

export function meRoutes() {
  return new Hono<{ Variables: AuthVariables }>().get('/', (c) => {
    const operador = c.get('operador');
    return c.json({
      id: operador.id,
      email: operador.email,
      name: operador.name,
      role: operador.role,
      permissions: isAdminRole(operador.role) ? ROLE_PERMISSIONS[operador.role] : [],
    });
  });
}
