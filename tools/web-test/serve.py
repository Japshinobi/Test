import http.server, os, sys, json
# Запуск: python3 serve.py <папка godot-проекта> [файл самопроверки .gd]
# Отдаёт index.html, движок (папка bin/, см. setup.sh) и файлы проекта по /proj/.
SITE = os.path.dirname(os.path.abspath(__file__)); BIN = os.path.join(SITE, 'bin')
PROJ = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(SITE, '..', '..', 'godot')
SELFTEST = sys.argv[2] if len(sys.argv) > 2 else os.environ.get('SELFTEST', os.path.join(SITE, 'selftest.example.gd'))
class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = path.split('?')[0]
        if p.startswith('/proj/'): return os.path.join(PROJ, p[6:])
        if p in ('/', '/index.html'): return os.path.join(SITE, 'index.html')
        return os.path.join(BIN, p.lstrip('/'))
    def do_GET(self):
        if self.path.startswith('/files.json'):
            out = []
            for d, dirs, fs in os.walk(PROJ):
                dirs[:] = [x for x in dirs if x != '.godot']
                for f in fs: out.append(os.path.relpath(os.path.join(d, f), PROJ))
            b = json.dumps(out).encode(); self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b); return
        if self.path.startswith('/proj/maps/farm.json'):
            import json as J
            from urllib.parse import urlparse, parse_qs
            q = {k: v[0] for k, v in parse_qs(urlparse(self.path).query).items()}
            d = J.load(open(self.translate_path(self.path), encoding='utf-8'))
            if 'sx' in q:
                for o in d['objects']:
                    if o['id'] == 'spawn': o['x'], o['y'] = int(q['sx']), int(q['sy'])
            b = J.dumps(d, ensure_ascii=False).encode(); self.send_response(200); self.end_headers(); self.wfile.write(b); return
        if self.path.startswith('/proj/') and self.path.split('?')[0].endswith('.gd'):
            src = open(self.translate_path(self.path), encoding='utf-8').read()
            # тестовая веб-сборка Godot собрана без сетевого модуля: подменяем сетевые классы заглушками
            src = (src.replace('peer is OfflineMultiplayerPeer', 'false')
                      .replace('OfflineMultiplayerPeer.new()', 'null')
                      .replace('var peer := ENetMultiplayerPeer.new()', 'var peer = ClassDB.instantiate("ENetMultiplayerPeer")')
                      .replace('var err := peer.', 'var err = peer.'))
            from urllib.parse import urlparse, parse_qs
            q = {k: v[0] for k, v in parse_qs(urlparse(self.path).query).items()}
            if 'friend' in q: src = src.replace('me.setup(atlas, false, "Ваня")', 'me.setup(atlas, true, "Нина")')
            if 'amb' in q: src = src.replace('env.ambient_light_energy = 0.4', 'env.ambient_light_energy = ' + q['amb'])
            if 'sun' in q: src = src.replace('sun.light_energy = 0.15 *', 'sun.light_energy = ' + q['sun'] + ' *')
            if 'farmtest' in q and self.path.split('?')[0].endswith('/main.gd'):
                src = src.replace('\n\n\nfunc _process', '\n\tcall_deferred("_selftest")\n\n\nfunc _process', 1) + open(SELFTEST, encoding='utf-8').read()
            if 'probe' in q and self.path.split('?')[0].endswith('/main.gd'):
                src = 'extends Node3D\nfunc _ready():\n\tprint("PROBE ", load("res://scripts/' + q['probe'] + '.gd"))\n'
            if 'loc' in q and self.path.split('?')[0].endswith('/main.gd'):
                src = src.replace('TESTLOC', '"' + q['loc'] + '"').replace('TESTPOS', 'Vector3(' + q.get('px', '20') + ', 0, ' + q.get('pz', '20') + ')')
            if 'day' in q: src = src.replace('var day := 1', 'var day := ' + q['day'])
            if 'min' in q: src = src.replace('var minutes := 7.0 * 60.0', 'var minutes := ' + q['min'] + '.0')
            if 'yaw' in q: src = src.replace('var yaw := 0.0', 'var yaw := ' + q['yaw'])
            if 'dist' in q: src = src.replace('var dist := 18.0', 'var dist := ' + q['dist'])
            b = src.encode(); self.send_response(200); self.end_headers(); self.wfile.write(b); return
        return super().do_GET()
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy','same-origin'); self.send_header('Cross-Origin-Embedder-Policy','require-corp'); self.send_header('Cache-Control','no-store'); super().end_headers()
    def log_message(self, *a): pass
H.extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.wasm':'application/wasm', '.mjs':'text/javascript', '.js':'text/javascript'}
print('http://127.0.0.1:8765/index.html  проект:', PROJ, flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1', 8765), H).serve_forever()
