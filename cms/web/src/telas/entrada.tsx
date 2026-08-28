/**
 * O fluxo de entrada, nas suas tres telas.
 *
 * Estao no mesmo arquivo porque sao um fluxo so, e a ordem entre elas e a parte
 * facil de errar — ver `api/entrada.ts` para o diagrama.
 *
 * ## LGPD-RT07: a tela nao conta tentativas
 *
 * A trava e por CONTA e progressiva (2 de folga, depois 30 s dobrando ate 15
 * min), e a resposta do servidor **nao diz quanto falta nem quantas restam** —
 * seria um oraculo sobre conta alheia. Aqui a mensagem do servidor e renderizada
 * LITERAL: nada de contador, nada de relogio, nada de "voce tem mais N
 * tentativas". Ha teste afirmando que nenhum digito aparece.
 */
import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';

import { acionar } from '../api/api.js';
import {
  CREDENCIAL_INVALIDA,
  conferirCodigo,
  entrar,
  type EstadoDaEntrada,
} from '../api/entrada.js';
import { useSessao } from '../sessao.js';

/** Para onde cada estado leva. Um lugar so, para as duas telas nao divergirem. */
function useDestino() {
  const navegar = useNavigate();
  const { recarregar } = useSessao();

  return async (estado: EstadoDaEntrada): Promise<string | undefined> => {
    switch (estado.estado) {
      case 'completa':
        await recarregar();
        navegar('/');
        return undefined;
      case 'pendente_codigo':
        navegar('/entrar/codigo');
        return undefined;
      case 'precisa_cadastrar':
        navegar('/entrar/cadastrar-2fa');
        return undefined;
      case 'travada':
        // LITERAL, do servidor. Ver o cabecalho do arquivo.
        return estado.mensagem;
      case 'recusada':
        return CREDENCIAL_INVALIDA;
    }
  };
}

function Erro({ texto }: { texto: string | undefined }) {
  if (!texto) return null;
  return (
    <p className="erro" role="alert">
      {texto}
    </p>
  );
}

export function TelaDeEntrada() {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string>();
  const [enviando, setEnviando] = useState(false);
  const destino = useDestino();

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro(undefined);
    setEnviando(true);
    try {
      setErro(await destino(await entrar(email, senha)));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <main className="cartao">
      <h1>Entrar</h1>
      <form onSubmit={enviar}>
        <label htmlFor="email">E-mail</label>
        <input
          id="email"
          type="email"
          autoComplete="username"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />

        <label htmlFor="senha">Senha</label>
        <input
          id="senha"
          type="password"
          autoComplete="current-password"
          required
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
        />

        <Erro texto={erro} />

        <button type="submit" disabled={enviando}>
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
      <p className="nota">
        Nao existe autocadastro. Uma conta e criada por um administrador, e o segundo fator e
        obrigatorio.
      </p>
    </main>
  );
}

export function TelaDeCodigo() {
  const [codigo, setCodigo] = useState('');
  const [erro, setErro] = useState<string>();
  const [enviando, setEnviando] = useState(false);
  const destino = useDestino();

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro(undefined);
    setEnviando(true);
    try {
      setErro(await destino(await conferirCodigo(codigo)));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <main className="cartao">
      <h1>Codigo do segundo fator</h1>
      <form onSubmit={enviar}>
        <label htmlFor="codigo">Codigo de 6 digitos</label>
        <input
          id="codigo"
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]{6}"
          maxLength={6}
          required
          value={codigo}
          onChange={(e) => setCodigo(e.target.value)}
        />

        <Erro texto={erro} />

        <button type="submit" disabled={enviando}>
          {enviando ? 'Conferindo…' : 'Conferir'}
        </button>
      </form>
    </main>
  );
}

/** O `secret` do `otpauth://` esta em base32 — e o que se digita a mao. */
function segredoDe(uri: string): string | undefined {
  try {
    return new URL(uri).searchParams.get('secret') ?? undefined;
  } catch {
    return undefined;
  }
}

export function TelaDeCadastroDe2fa() {
  const [senha, setSenha] = useState('');
  const [uri, setUri] = useState<string>();
  const [qr, setQr] = useState<string>();
  const [erro, setErro] = useState<string>();
  const [enviando, setEnviando] = useState(false);

  async function cadastrar(e: FormEvent) {
    e.preventDefault();
    setErro(undefined);
    setEnviando(true);
    try {
      const { totpURI } = await acionar<{ totpURI: string }>('/api/auth/two-factor/enable', {
        password: senha,
      });
      setUri(totpURI);
      try {
        // Carregado sob demanda: quem ja tem 2FA nunca passa por aqui, e a
        // biblioteca nao precisa entrar no bundle inicial de todo mundo.
        const { toDataURL } = await import('qrcode');
        setQr(await toDataURL(totpURI, { margin: 1, width: 220 }));
      } catch {
        // QR e conveniencia; a chave base32 abaixo dele e o que de fato cadastra.
        // Deixar esta falha subir marcaria como FRACASSO um cadastro que
        // funcionou — o segredo ja esta na tela, pronto para ser digitado. Sem
        // este isolamento, um ambiente sem canvas (jsdom, ou um navegador com
        // restricao) transformaria "sem QR" em "nao consegui cadastrar".
      }
    } catch {
      setErro('Nao foi possivel cadastrar. Confira a senha e tente de novo.');
    } finally {
      setEnviando(false);
    }
  }

  if (uri) {
    const segredo = segredoDe(uri);
    return (
      <main className="cartao">
        <h1>Cadastrar segundo fator</h1>
        <p>Leia o codigo abaixo no seu aplicativo autenticador.</p>
        {qr && <img src={qr} alt="QR code do segundo fator" width={220} height={220} />}
        {segredo && (
          <>
            <p className="nota">Ou digite a chave a mao:</p>
            <code className="segredo">{segredo}</code>
          </>
        )}
        {/*
          A parte que engana. `two-factor/enable` NAO liga a 2FA: ele entrega o
          segredo, deixa `verified = 0` e REVOGA a sessao. A ativacao acontece na
          primeira verificacao bem-sucedida, num login NOVO.

          Por isso esta tela nao chama `/api/me` depois — a resposta seria 401, e
          pareceria defeito. E por isso ela manda entrar de novo, em vez de
          oferecer um campo de codigo aqui: o codigo digitado aqui nao teria
          sessao para ativar.
        */}
        <p role="alert" className="aviso">
          <strong>Entre de novo</strong> para concluir: o cadastro so e ativado na primeira
          verificacao bem-sucedida, num login novo.
        </p>
        <a href="/entrar">Ir para a entrada</a>
      </main>
    );
  }

  return (
    <main className="cartao">
      <h1>Cadastrar segundo fator</h1>
      <p>
        O segundo fator e obrigatorio. Sua conta nao alcanca nenhuma tela ate ele estar ativo — nao
        e um aviso, e o servidor recusando.
      </p>
      {/*
        `/api/me` responde o MESMO 403 para dois estados diferentes: "nunca
        cadastrou" e "cadastrou e ainda nao verificou" (a ativacao so acontece na
        primeira verificacao bem-sucedida). O cliente nao tem como distinguir —
        e adivinhar erra metade das vezes.

        Entao a tela pergunta, em vez de decidir. Sem esta saida, quem ja guardou
        a chave no autenticador so encontraria o botao de gerar OUTRA, o que
        invalidaria a que acabou de cadastrar.
      */}
      <p className="nota">
        Ja tem a chave no seu autenticador? <Link to="/entrar/codigo">Digite o codigo</Link>.
      </p>
      <form onSubmit={cadastrar}>
        {/*
          Campo de senha proprio. O Better Auth exige a senha para entregar o
          segredo, e carregar a senha da tela anterior em memoria entre rotas e
          pior que pedi-la uma vez a mais.
        */}
        <label htmlFor="senha-2fa">Confirme sua senha</label>
        <input
          id="senha-2fa"
          type="password"
          autoComplete="current-password"
          required
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
        />

        <Erro texto={erro} />

        <button type="submit" disabled={enviando}>
          {enviando ? 'Gerando…' : 'Gerar chave'}
        </button>
      </form>
    </main>
  );
}
