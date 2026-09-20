#!/usr/bin/env python3
"""CLAN AI — web QA fixture server (llama.cpp / OpenAI-compatible shape).

Deterministic stand-in for `llama-server` used by the Phase-3 web QA suite
(integration_test/phase3_web_qa_test.dart) and manual browser QA. Exact
llama.cpp response shapes for /health, /props, /v1/models and an SSE
/v1/chat/completions stream with reasoning_content ([DONE]-terminated).

Endpoints
    GET  /health                -> {"status":"ok"}
    GET  /props                 -> llama.cpp server props
    GET  /v1/models             -> model list (deduped by id in the app)
    POST /v1/chat/completions   -> SSE stream (or JSON when stream=false)
    OPTIONS *                   -> CORS preflight (Authorization allowed)

Behavioural knobs (argv):
    --port 8090            listen port
    --delay 80             ms between stream chunks (0 = as fast as possible)
    --reasoning            emit `reasoning_content` on the first chunks
    --slow-ttft 2.0        hold the response open this many seconds before the
                           first chunk (simulates server prefill -> TTFT)
    --api-key <key>        require `Authorization: Bearer <key>` (401 otherwise)
    --tokens 6             number of content tokens to stream
    --stall-prefix STALL   when the last user message starts with this prefix,
                           stream one content token then idle watching for a
                           client disconnect (used by the stop/cancel test);
                           `select()` on the socket reports an abort promptly
                           instead of on the next write

CORS mirrors the real llama-server defaults: echo the Origin and allow
`authorization`/`content-type` through preflight (verified against the
running llama-server on 127.0.0.1:8080).
"""
import argparse
import json
import select
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

LOG_PATH = '/tmp/opencode/qa-server.log'
ARGS = None

MODEL_ID = 'qa-fixture-8b'


def log(msg):
    line = f'{time.time():.3f} {msg}'
    with open(LOG_PATH, 'a') as f:
        f.write(line + '\n')
    print(line, flush=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    # ---- CORS -----------------------------------------------------------
    def _cors(self, origin=None):
        if origin:
            self.send_header('Access-Control-Allow-Origin', origin)
        else:
            self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Credentials', 'true')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'content-type, authorization, accept')

    def _auth_ok(self):
        if not ARGS.api_key:
            return True
        header = self.headers.get('Authorization', '')
        return header == f'Bearer {ARGS.api_key}'

    def _unauthorized(self, origin):
        body = json.dumps({
            'error': {
                'message': 'Invalid API Key',
                'type': 'authentication_error',
                'code': 401,
            }
        }).encode()
        self.send_response(401)
        self._cors(origin)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        log(f'401 {self.command} {self.path}')

    # ---- helpers --------------------------------------------------------
    def _origin(self):
        return self.headers.get('Origin')

    def do_OPTIONS(self):
        origin = self._origin()
        self.send_response(204)
        self._cors(origin)
        self.send_header('Content-Length', '0')
        self.end_headers()
        log(f'OPTIONS {self.path} origin={origin}')

    def do_GET(self):
        origin = self._origin()
        path = urlparse(self.path).path
        # /health is auth-exempt like llama.cpp; everything else requires the key.
        if path != '/health' and not self._auth_ok():
            return self._unauthorized(origin)
        if path == '/health':
            body = b'{"status":"ok"}'
            status = 200
        elif path == '/props':
            body = json.dumps({
                'default_generation_settings': {
                    'params': {
                        'seed': 4294967295, 'temperature': 1.0, 'top_k': 20,
                        'top_p': 0.949999988079071, 'min_p': 0.05,
                        'repeat_last_n': 64, 'repeat_penalty': 1.1,
                        'n_ctx': 131072, 'n_predict': -1,
                    },
                    'max_n_ctx': 131072, 'model_path': MODEL_ID,
                },
                'model_path': MODEL_ID,
                'system_prompt': False,
                'total_slots': 1,
            }).encode()
            status = 200
        elif path == '/v1/models':
            body = json.dumps({
                'models': [{
                    'name': MODEL_ID, 'model': MODEL_ID,
                    'modified_at': '', 'size': '', 'digest': '',
                    'type': 'model', 'description': '', 'tags': [''],
                    'capabilities': ['completion', 'multimodal'],
                    'parameters': '',
                }]
            }).encode()
            status = 200
        else:
            body = json.dumps({'error': {'message': 'Not Found', 'type': 'not_found'}}).encode()
            status = 404
        self.send_response(status)
        self._cors(origin)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        log(f'GET {path} -> {status} origin={origin}')

    # ---- chat completions -----------------------------------------------
    def do_POST(self):
        origin = self._origin()
        path = urlparse(self.path).path
        if path != '/v1/chat/completions':
            body = json.dumps({'error': {'message': 'Not Found'}}).encode()
            self.send_response(404)
            self._cors(origin)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length) if length else b'{}'
        try:
            req = json.loads(raw)
        except Exception:
            req = {}
        if not self._auth_ok():
            return self._unauthorized(origin)

        stream = req.get('stream', False)
        has_image = 'data:image/' in raw.decode('utf-8', 'replace')
        log(f'POST /v1/chat/completions stream={stream} image={has_image} '
            f'body_len={len(raw)} auth={"yes" if self.headers.get("Authorization") else "no"} '
            f'origin={origin}')

        if not stream:
            body = json.dumps({
                'id': 'chatcmpl-qa', 'object': 'chat.completion',
                'created': int(time.time()), 'model': MODEL_ID,
                'choices': [{
                    'index': 0,
                    'message': {'role': 'assistant', 'content': ' '.join(
                        f'token-{i}' for i in range(ARGS.tokens))},
                    'finish_reason': 'stop',
                }],
                'usage': {'prompt_tokens': 8, 'completion_tokens': ARGS.tokens,
                          'total_tokens': 8 + ARGS.tokens},
            }).encode()
            self.send_response(200)
            self._cors(origin)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # Streaming response.
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self._cors(origin)
        self.end_headers()
        started = time.time()
        stream_begin = started + (ARGS.slow_ttft or 0.0)
        if stream_begin > started:
            time.sleep(stream_begin - started)

        # Deterministic cancellation trigger: if the last user message starts
        # with the stall prefix, emit one content token then idle until the
        # client aborts (or a hard cap).
        last_user = ''
        for m in req.get('messages', []):
            if isinstance(m, dict) and m.get('role') == 'user':
                last_user = str(m.get('content', ''))
        stall = ARGS.stall_prefix and ARGS.stall_prefix in last_user

        def send_chunk(payload):
            self.wfile.write(f'data: {payload}\n\n'.encode())
            self.wfile.flush()

        try:
            i = 0
            # First chunk carries the role; reasoning goes here when enabled.
            delta = {'role': 'assistant', 'content': ''}
            if ARGS.reasoning:
                delta['reasoning_content'] = 'qa-reasoning part one'
            send_chunk(json.dumps({
                'id': f'chatcmpl-qa-{i}', 'object': 'chat.completion.chunk',
                'created': int(time.time()), 'model': MODEL_ID,
                'choices': [{'index': 0, 'delta': delta, 'finish_reason': None}],
            }))
            i += 1
            log(f'  first chunk after {time.time() - started:.3f}s')
            for n in range(ARGS.tokens):
                delta = {'content': f' tok-{n}'}
                if ARGS.reasoning and n == 0:
                    delta['reasoning_content'] = ' part two'
                send_chunk(json.dumps({
                    'id': f'chatcmpl-qa-{i}', 'object': 'chat.completion.chunk',
                    'created': int(time.time()), 'model': MODEL_ID,
                    'choices': [{'index': 0, 'delta': delta, 'finish_reason': None}],
                }))
                i += 1
                if stall and n == 0:
                    # Idle-hold: watch the socket for a client abort so the
                    # fixture can log the disconnect promptly.
                    idle_began = time.time()
                    aborted = False
                    while time.time() - idle_began < 90:
                        r, _, _ = select.select([self.connection], [], [], 0.5)
                        if r:
                            try:
                                if self.connection.recv(1) == b'':
                                    aborted = True
                                    break
                            except OSError:
                                aborted = True
                                break
                        if self.connection.fileno() < 0:
                            aborted = True
                            break
                    log(f'  stall released: client {"" if aborted else "did not"} '
                        f'disconnect after {time.time() - idle_began:.2f}s')
                    if aborted:
                        return
                if ARGS.delay:
                    time.sleep(ARGS.delay / 1000.0)
            send_chunk(json.dumps({
                'id': f'chatcmpl-qa-{i}', 'object': 'chat.completion.chunk',
                'created': int(time.time()), 'model': MODEL_ID,
                'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}],
            }))
            self.wfile.write(b'data: [DONE]\n\n')
            self.wfile.flush()
            log(f'  stream complete in {time.time() - started:.3f}s')
        except (BrokenPipeError, ConnectionResetError, OSError) as e:
            log(f'  client disconnected mid-stream after '
                f'{time.time() - started:.3f}s ({type(e).__name__})')
        finally:
            try:
                self.wfile.close()
            except Exception:
                pass

    def log_message(self, *a):
        pass


def main():
    global ARGS
    p = argparse.ArgumentParser()
    p.add_argument('--port', type=int, default=8090)
    p.add_argument('--delay', type=int, default=80, help='ms between chunks')
    p.add_argument('--tokens', type=int, default=6)
    p.add_argument('--reasoning', action='store_true')
    p.add_argument('--slow-ttft', type=float, default=0.0,
                   help='seconds to hold before the first chunk')
    p.add_argument('--stall-prefix', default='STALL',
                   help='prompt prefix that triggers a frozen stream')
    p.add_argument('--api-key', default=None,
                   help=argparse.SUPPRESS if False else
                   'require Bearer auth (401 otherwise)')
    ARGS = p.parse_args()
    with open(LOG_PATH, 'w'):
        pass
    ThreadingHTTPServer(('127.0.0.1', ARGS.port), Handler).serve_forever()


if __name__ == '__main__':
    main()