#!/usr/bin/env python3
"""Entrega ao receptor OAuth do Kiro a URL que o navegador não alcançou.

Rode na mesma máquina/WSL do Kiro, mantendo a sessão original aberta.
Os dois links são lidos sem eco; não os coloque em argumentos ou no chat.
Este auxiliar não troca códigos por tokens e não segue redirecionamentos.
"""
import contextlib
import argparse
import getpass
import hmac
import http.client
import re
import subprocess
import sys
import urllib.parse


class ErroRetorno(ValueError):
    """Mensagem controlada, sem reproduzir URLs ou dados recebidos."""


def unico(query, nome):
    valores = query.get(nome, [])
    if len(valores) != 1 or not valores[0]:
        raise ErroRetorno('parâmetro OAuth ausente ou repetido: ' + nome)
    return valores[0]


def local(url):
    if len(url) > 32768 or any(c in url for c in '\r\n\t'):
        raise ErroRetorno('URL inválida')
    u = urllib.parse.urlsplit(url)
    if (u.scheme != 'http' or u.hostname not in ('127.0.0.1', 'localhost')
            or not u.port or u.username or u.password or u.fragment):
        raise ErroRetorno('retorno deve usar HTTP loopback com porta explícita')
    return u


def destino(autorizacao, retorno):
    """Valida origem, caminho e state antes de qualquer conexão local."""
    a = urllib.parse.urlsplit(autorizacao)
    if (a.scheme != 'https' or a.hostname not in ('www.figma.com', 'figma.com')
            or a.path != '/oauth/mcp' or a.username or a.password
            or a.port not in (None, 443) or a.fragment):
        raise ErroRetorno('use o link oficial OAuth do Figma apresentado pelo Kiro')
    aq = urllib.parse.parse_qs(a.query, keep_blank_values=True)
    esperado = local(unico(aq, 'redirect_uri'))
    recebido = local(retorno)
    if (recebido.hostname, recebido.port, recebido.path or '/') != (
            esperado.hostname, esperado.port, esperado.path or '/'):
        raise ErroRetorno('retorno não corresponde ao redirect_uri desta tentativa')
    rq = urllib.parse.parse_qs(recebido.query, keep_blank_values=True)
    if not hmac.compare_digest(unico(aq, 'state').encode(), unico(rq, 'state').encode()):
        raise ErroRetorno('state não corresponde à tentativa do Kiro')
    if 'error' in rq:
        raise ErroRetorno('provedor recusou a autorização; inicie outra tentativa')
    unico(rq, 'code')
    return recebido.port, (recebido.path or '/') + '?' + recebido.query


def entregar(autorizacao, retorno):
    porta, caminho = destino(autorizacao, retorno)
    # Conexão direta: não resolve localhost por DNS, não usa proxy nem segue Location.
    with contextlib.closing(http.client.HTTPConnection('127.0.0.1', porta, timeout=10)) as c:
        c.request('GET', caminho, headers={'Connection': 'close'})
        with c.getresponse() as resposta:
            if not 200 <= resposta.status < 300:
                raise ErroRetorno('receptor recusou o retorno (HTTP %d)' % resposta.status)


def autorizacao_tt(sessao):
    if not re.fullmatch(r'[A-Za-z0-9_-]+', sessao):
        raise ErroRetorno('nome de sessão inválido')
    tela = subprocess.run(['tt', '--pty', 'ler', sessao, '200'], check=True,
                          capture_output=True, text=True, timeout=10).stdout
    links = re.findall(r'https://(?:www\.)?figma\.com/oauth/mcp\?[^\s]+', tela)
    if not links:
        raise ErroRetorno('link OAuth não encontrado na sessão; abra /mcp no Kiro')
    return links[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sessao', help='nome do terminal tt --pty onde o Kiro mostra /mcp')
    args = parser.parse_args()
    if not sys.stdin.isatty():
        print('Abra um terminal interativo na máquina do Kiro para colar os links sem eco.', file=sys.stderr)
        return 2
    try:
        autorizacao = (autorizacao_tt(args.sessao) if args.sessao else
                       getpass.getpass('Link de autorização mostrado por /mcp (oculto): ').strip())
        retorno = getpass.getpass('URL final do navegador com code e state (oculta): ').strip()
        entregar(autorizacao, retorno)
    except (ValueError, OSError, http.client.HTTPException, EOFError, KeyboardInterrupt,
            subprocess.SubprocessError) as e:
        if isinstance(e, ErroRetorno):
            print(str(e), file=sys.stderr)
        elif isinstance(e, ValueError):
            print('Link inválido: confira origem, porta, caminho, code e state da mesma tentativa.', file=sys.stderr)
        else:
            print('Não foi possível entregar o retorno. Confira se a sessão Kiro original continua aguardando.', file=sys.stderr)
        return 1
    print('Retorno entregue ao receptor local. Confira no Kiro se o MCP foi carregado; entrega não comprova troca de token.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
