/**
 * Quem esta usando a interface, durante a vida da aba.
 *
 * O estado vive em memoria e some ao recarregar — de proposito. A sessao de
 * verdade e o cookie `httpOnly` do Better Auth, que script nenhum enxerga;
 * guardar uma copia do operador em `localStorage` criaria uma segunda resposta
 * para "quem esta logado", que pode divergir da primeira e sobrevive ao logout.
 *
 * `permissions` vem resolvido pelo servidor e serve para DESENHAR. Quem autoriza
 * e o `requirePermission` de cada rota.
 */
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

import { buscar } from './api/api.js';
import type { Operador } from './api/erros.js';

interface Sessao {
  operador: Operador | undefined;
  carregando: boolean;
  recarregar: () => Promise<void>;
  esquecer: () => void;
}

const Contexto = createContext<Sessao | undefined>(undefined);

export function SessaoProvider({
  children,
  inicial,
}: {
  children: ReactNode;
  /** So o teste informa, para nao ter que simular o carregamento em toda tela. */
  inicial?: Operador;
}) {
  const [operador, setOperador] = useState<Operador | undefined>(inicial);
  const [carregando, setCarregando] = useState(inicial === undefined);

  const recarregar = useCallback(async () => {
    setCarregando(true);
    try {
      setOperador(await buscar<Operador>('/api/me'));
    } catch {
      // 401 e 403 ja dispararam os avisos globais de `api.ts`, que navegam. Aqui
      // so registramos a ausencia — insistir levaria a um laco de requisicoes
      // contra um servidor que ja respondeu "nao".
      setOperador(undefined);
    } finally {
      setCarregando(false);
    }
  }, []);

  const esquecer = useCallback(() => setOperador(undefined), []);

  useEffect(() => {
    if (inicial === undefined) void recarregar();
    // `inicial` so existe em teste e nunca muda depois da montagem.
  }, [inicial, recarregar]);

  return (
    <Contexto.Provider value={{ operador, carregando, recarregar, esquecer }}>
      {children}
    </Contexto.Provider>
  );
}

export function useSessao(): Sessao {
  const valor = useContext(Contexto);
  if (!valor) throw new Error('useSessao fora de <SessaoProvider>');
  return valor;
}
