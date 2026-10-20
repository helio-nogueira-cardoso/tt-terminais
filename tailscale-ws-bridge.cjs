'use strict';
const http = require('node:http');
const https = require('node:https');
const net = require('node:net');
const control = new Set(['controlplane.tailscale.com', 'login.tailscale.com']);
const isDerp = host => /^derp[0-9]+[a-z]*\.tailscale\.com$/.test(host);
const controlProtocol = 'tailscale-control-protocol';
const log = message => console.log(new Date().toISOString(), message);

function destination(req) {
  const url = new URL(req.url, 'http://' + req.headers.host);
  if (!control.has(url.hostname)) throw new Error('destination denied');
  return url;
}

function websocketBridge(client, head, url, protocol, upgrade) {
  const ws = new WebSocket(url, protocol);
  ws.binaryType = 'arraybuffer';
  let opened = false, sent = 0, received = 0;
  const tag = protocol + ' ' + url.hostname;
  const deadline = setTimeout(() => { log(tag + ' handshake timeout'); client.destroy(); ws.close(); }, 20000);
  ws.addEventListener('open', () => {
    opened = true; clearTimeout(deadline);
    if (client.destroyed) return ws.close();
    log(tag + ' connected');
    client.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: ' + upgrade + '\r\nConnection: upgrade\r\n\r\n');
    if (head.length) ws.send(head);
    client.on('data', data => { sent += data.length; if (ws.readyState === 1) ws.send(data); });
  });
  ws.addEventListener('message', event => {
    if (typeof event.data === 'string') return client.destroy();
    const data = Buffer.from(event.data); received += data.length;
    if (!client.destroyed) client.write(data);
  });
  ws.addEventListener('error', event => { clearTimeout(deadline); log(tag + ' error: ' + (event.message || 'connection failure')); client.destroy(); });
  ws.addEventListener('close', event => { clearTimeout(deadline); log(tag + ' closed code=' + event.code + ' sent=' + sent + ' received=' + received); client.end(); });
  client.on('error', () => { if (opened) ws.close(); });
  client.on('close', () => { clearTimeout(deadline); if (opened) ws.close(); });
}

const server = http.createServer((req, res) => {
  let url;
  try { url = destination(req); } catch (_) { return res.writeHead(403).end(); }
  if (url.pathname !== '/key') return res.writeHead(404).end();
  const upstream = https.get('https://' + url.hostname + url.pathname + url.search, response => {
    res.writeHead(response.statusCode, {'Content-Type': 'application/json'}); response.pipe(res);
  });
  upstream.on('error', error => { log('key request failed: ' + error.code); res.writeHead(502).end(); });
});

server.on('connect', (req, client, head) => {
  const parts = req.url.split(':'), host = parts[0], port = Number(parts[1]);
  if (parts.length !== 2 || (!control.has(host) && !isDerp(host))) return client.end('HTTP/1.1 403 Forbidden\r\n\r\n');
  if (port === 3340 && isDerp(host)) {
    client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    let buffer = head; const timer = setTimeout(() => client.destroy(), 10000);
    function parse(data) {
      buffer = Buffer.concat([buffer, data]);
      if (buffer.length > 16384) return client.destroy();
      const end = buffer.indexOf('\r\n\r\n'); if (end < 0) return;
      clearTimeout(timer); client.off('data', parse);
      const header = buffer.subarray(0, end).toString('latin1');
      if (!/^GET \/derp(?:\?[^ ]*)? HTTP\/1\.[01]\r\n/.test(header) || !/\r\nUpgrade: DERP\r?$/im.test(header)) return client.end('HTTP/1.1 400 Bad Request\r\n\r\n');
      websocketBridge(client, buffer.subarray(end + 4), new URL('wss://' + host + '/derp'), 'derp', 'DERP');
    }
    client.on('data', parse); client.on('error', () => clearTimeout(timer));
    if (head.length) parse(Buffer.alloc(0));
    return;
  }
  if (port !== 443) return client.end('HTTP/1.1 403 Forbidden\r\n\r\n');
  const upstream = net.connect(443, host, () => {
    client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    if (head.length) upstream.write(head); client.pipe(upstream); upstream.pipe(client);
  });
  upstream.on('error', () => client.destroy()); client.on('error', () => upstream.destroy()); client.on('close', () => upstream.destroy());
});

server.on('upgrade', (req, client, head) => {
  let url;
  try { url = destination(req); } catch (_) { return client.end('HTTP/1.1 403 Forbidden\r\n\r\n'); }
  if (url.pathname !== '/ts2021' || req.headers.upgrade !== controlProtocol || !req.headers['x-tailscale-handshake']) return client.end('HTTP/1.1 400 Bad Request\r\n\r\n');
  const target = new URL('wss://' + url.hostname + '/ts2021');
  target.searchParams.set('X-Tailscale-Handshake', req.headers['x-tailscale-handshake']);
  websocketBridge(client, head, target, controlProtocol, controlProtocol);
});
server.on('clientError', (_, socket) => socket.destroy());
const port = Number(process.env.BRIDGE_PORT || 18744);
server.listen(port, '127.0.0.1', () => log('listening on 127.0.0.1:' + port));
