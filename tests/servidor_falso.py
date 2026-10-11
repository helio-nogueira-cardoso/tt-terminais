#!/usr/bin/env python3
"""Servidor de mentira para tests/test_letreiro_fontes.sh — nunca a rede real.

  servidor_falso.py PORTA [CERT CHAVE]     http (ou https, com certificado) em 127.0.0.1:PORTA

Rotas (o corpo diz o que cada uma testa):
  /dolar /awesome /btc /texto /lista    respostas curtas (JSON/texto) como as APIs de verdade
  /rss /atom /xml /csv /regex           formatos de resposta
  /eco                                  devolve método, caminho, query, corpo e cabeçalhos (testa auth/POST)
  /contador                             {"n": N}: N cresce a cada chamada (testa TTL e variação calculada)
  /valor?v=X                            {"v": "X"} (valor escolhido pelo teste)
  /flaky?ate=N                          500 nas N primeiras chamadas, depois 200
  /erro500 /erro404 /429                códigos HTTP
  /lento?s=S                            espera S segundos antes de responder
  /grande?kb=K                          K KB de lixo (testa tamanho_max)
  /gzip /bomba-gzip                     resposta comprimida (e uma "bomba" que descomprime enorme)
  /redir?para=URL&c=302                 redireciona para URL      /loop  redireciona para si mesma
  /ataque                               JSON com escapes de terminal, #[ #( e controles de direção
  /xml-bomba                            XML com DOCTYPE/ENTITY (expansão de entidades)
  /_hits?p=/caminho                     quantas vezes /caminho foi chamado
  /_ultimo?p=/caminho                   o último pedido que /caminho recebeu (método, cabeçalhos, corpo)
"""
import gzip
import http.server
import json
import ssl
import sys
import threading
import time
import urllib.parse

HITS = {}
ULTIMO = {}
LOCK = threading.Lock()


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_GET(self):
        self.tratar()

    def do_POST(self):
        self.tratar()

    def enviar(self, corpo, ct="application/json", codigo=200, extra=None):
        b = corpo if isinstance(corpo, bytes) else corpo.encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Connection", "close")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)

    def tratar(self):
        u = urllib.parse.urlsplit(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        n = int(self.headers.get("Content-Length") or 0)
        corpo = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        p = u.path
        if p == "/_hits":
            with LOCK:
                return self.enviar(str(HITS.get(q.get("p", ""), 0)), "text/plain")
        if p == "/_ultimo":
            with LOCK:
                return self.enviar(json.dumps(ULTIMO.get(q.get("p", ""), {})))
        with LOCK:
            HITS[p] = HITS.get(p, 0) + 1
            hits = HITS[p]
            ULTIMO[p] = {"metodo": self.command, "auth": self.headers.get("Authorization"), "key": self.headers.get("X-API-Key"),
                         "ua": self.headers.get("User-Agent"), "corpo": corpo, "path": self.path, "ct": self.headers.get("Content-Type"),
                         "cookie": self.headers.get("Cookie"), "extra": self.headers.get("X-Extra"), "host": self.headers.get("Host")}
        if p in ("/dolar", "/awesome"):
            return self.enviar(json.dumps({"USDBRL": {"bid": "5.1234", "pctChange": "0.52"}}))
        if p == "/btc":
            return self.enviar(json.dumps({"data": {"base": "BTC", "amount": "67890.12"}}))
        if p == "/texto":
            return self.enviar("primeira linha do texto\nsegunda\n", "text/plain")
        if p == "/lista":
            return self.enviar(json.dumps({"a": [{"x": "zero"}, {"x": "um"}, {"x": "dois"}],
                                           "itens": [{"nome": "a", "v": 1, "d": "2026-01-01"}, {"nome": "b", "v": 2, "d": "2026-12-31"}, {"nome": "c", "v": 3, "d": "2027-06-01"}]}))
        if p == "/rss":
            return self.enviar("<rss><channel><item><title> Manchete A do g1 </title><link>https://exemplo.com/a</link><description>&lt;b&gt;negrito&lt;/b&gt; resumo</description></item>"
                               "<item><title>Manchete B</title><link>https://exemplo.com/b</link></item><item><title>C nao entra</title></item></channel></rss>", "application/xml")
        if p == "/rss-bbc":
            return self.enviar("<rss><channel><item><title>World one</title></item><item><title>World two</title></item></channel></rss>", "application/xml")
        if p == "/atom":
            return self.enviar('<?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title>F</title>'
                               '<entry><title>Entrada 1</title><link href="https://exemplo.com/e1"/></entry><entry><title>Entrada 2</title><link href="https://exemplo.com/e2"/></entry></feed>', "application/atom+xml")
        if p == "/xml":
            return self.enviar('<dados><item id="1" tipo="x"><nome>Um</nome><preco>10,50</preco></item><item id="2" tipo="y"><nome>Dois</nome><preco>20,00</preco></item></dados>', "text/xml")
        if p == "/csv":
            return self.enviar("data,valor,nome\n2026-01-01,10,alfa\n2026-01-02,12.5,beta\n2026-01-03,15,gama\n", "text/csv")
        if p == "/csv-pv":
            return self.enviar("data;valor\n01/01;1.234,56\n02/01;1.300,00\n", "text/csv")
        if p == "/regex":
            return self.enviar("temperatura: 21.3 C | umidade: 80 % | vento: 12 km/h\ntemperatura: 25.0 C\n", "text/plain")
        if p == "/eco":
            return self.enviar(json.dumps({"metodo": self.command, "caminho": p, "query": q, "corpo": corpo,
                                           "auth": self.headers.get("Authorization"), "key": self.headers.get("X-API-Key"),
                                           "ua": self.headers.get("User-Agent"), "ct": self.headers.get("Content-Type"),
                                           "x_extra": self.headers.get("X-Extra"), "full": self.path}))
        if p == "/contador":
            return self.enviar(json.dumps({"n": hits}))
        if p == "/valor":
            return self.enviar(json.dumps({"v": q.get("v", "0"), "p": q.get("p", "0")}))
        if p == "/flaky":
            if hits <= int(q.get("ate", "1")):
                return self.enviar("falhou", "text/plain", 500)
            return self.enviar(json.dumps({"ok": "passou"}))
        if p == "/erro500":
            return self.enviar("erro interno", "text/plain", 500)
        if p == "/erro404":
            return self.enviar("nada aqui", "text/plain", 404)
        if p == "/429":
            return self.enviar("devagar", "text/plain", 429, {"Retry-After": "0"})
        if p == "/lento":
            time.sleep(float(q.get("s", "3")))
            return self.enviar(json.dumps({"ok": "demorou"}))
        if p == "/grande":
            return self.enviar(json.dumps({"lixo": "x" * (int(q.get("kb", "10")) * 1024)}))
        if p == "/gzip":
            return self.enviar(gzip.compress(json.dumps({"z": "comprimido"}).encode()), extra={"Content-Encoding": "gzip"})
        if p == "/bomba-gzip":
            return self.enviar(gzip.compress(b"0" * (64 * 1024 * 1024), 9), extra={"Content-Encoding": "gzip"})
        if p == "/loop":
            return self.enviar("", "text/plain", 302, {"Location": "/loop"})
        if p == "/redir":
            return self.enviar("", "text/plain", int(q.get("c", "302")), {"Location": q.get("para", "/")})
        if p == "/ataque":
            return self.enviar(json.dumps({"t": "ok \x1b[31mVERMELHO\x1b[0m \x1b]0;titulo\x07 #[fg=red,bold] #(touch /tmp/pwn) #{pane_pid} ‮RTL⁩ fim\x07\x08",
                                           "t2": "#[range=user|letreiro]clique#[norange]", "t3": "a\rb\nc\td"}, ensure_ascii=False))
        if p == "/xml-bomba":
            return self.enviar('<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]><r><t>&b;</t></r>', "application/xml")
        self.enviar("não existe", "text/plain", 404)


def main():
    porta = int(sys.argv[1])
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", porta), H)
    srv.daemon_threads = True
    if len(sys.argv) >= 4:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(sys.argv[2], sys.argv[3])
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    print("pronto", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
