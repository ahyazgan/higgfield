#!/usr/bin/env python3
"""serve.py — NORTH için bağımlılıksız (saf stdlib) yerel web paneli.

Sahneleri missions.json'dan listeler; tarayıcıdan Doğrula / Önizle (dry-run) /
Üret / Videoya çevir butonlarıyla mevcut scriptleri çalıştırır. Harici paket yok.

Kullanım:  python3 serve.py            -> http://127.0.0.1:8000
           PORT=9000 python3 serve.py
Sadece 127.0.0.1'e bağlanır (yerel kullanım).
"""
import json
import os
import re
import secrets
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", "8000"))
# Eylem ucu (/api/run) için token. PANEL_TOKEN ile sabitlenebilir; yoksa her
# başlatmada üretilir. Sayfaya server enjekte eder (tarayıcı otomatik gönderir);
# özel başlık (X-Panel-Token) ayrıca CSRF'ye karşı preflight zorlar.
TOKEN = os.environ.get("PANEL_TOKEN") or secrets.token_urlsafe(16)

MISSION_RE = re.compile(r"^0[0-9]$")
SCENE_RE = re.compile(r"^[0-9]$")

# Güvenli komut allowlist'i — kullanıcı girdisi asla shell'e geçmez.
def build_cmd(action, mission, scene, dry):
    m = mission if MISSION_RE.match(mission or "") else "01"
    base = ["./generate.sh"]
    if action == "check":
        return base + ["--check", m]
    if action == "generate":
        cmd = base + (["--dry-run"] if dry else [])
        cmd += [m]
        if scene and SCENE_RE.match(scene):
            cmd += [scene]
        return cmd
    if action == "video":
        c = ["./to_video.sh"] + (["--dry-run"] if dry else []) + ["out/latest"]
        return c
    if action == "contact":
        return ["./contact_sheet.sh", "out/latest"]
    if action == "costs":
        return ["./costs.sh"]
    return None


def run(cmd):
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=600)
        # ANSI renk kodlarını temizle
        out = re.sub(r"\x1b\[[0-9;]*m", "", (p.stdout or "") + (p.stderr or ""))
        return p.returncode, out
    except Exception as e:
        return 1, f"çalıştırma hatası: {e}"


def scenes_data():
    with open(os.path.join(ROOT, "missions.json"), encoding="utf-8") as f:
        d = json.load(f)
    out = {}
    for mid, m in d.get("missions", {}).items():
        out[mid] = {"title": m.get("title", ""),
                    "scenes": [{"id": s["id"], "title": s["title"],
                                "camera": s["camera"], "location": s["location"]}
                               for s in m.get("scenes", [])]}
    return out


INDEX = """<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>NORTH paneli</title>
<style>
 body{background:#0f1115;color:#e6e6e6;font:14px/1.5 system-ui,sans-serif;margin:0;padding:24px;max-width:1100px;margin:auto}
 h1{font-size:20px} h2{font-size:15px;color:#7ec8ff;margin:18px 0 8px}
 .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:6px 0}
 button{background:#1f6feb;color:#fff;border:0;border-radius:6px;padding:6px 12px;cursor:pointer;font-size:13px}
 button.alt{background:#2d333b} button.go{background:#2ea043}
 select{background:#161b22;color:#eee;border:1px solid #30363d;border-radius:6px;padding:5px}
 label.chk{font-size:12px;color:#aaa} table{border-collapse:collapse;width:100%;margin-top:6px}
 td,th{border:1px solid #21262d;padding:4px 8px;text-align:left;font-size:12px}
 pre{background:#0b0e13;border:1px solid #21262d;border-radius:8px;padding:12px;white-space:pre-wrap;max-height:420px;overflow:auto}
 .muted{color:#8b949e;font-size:12px}
</style></head><body>
<h1>NORTH üretim paneli <span class="muted">(yerel)</span></h1>
<div class="row">
  <label class="chk"><input type="checkbox" id="dry" checked> dry-run (kredi harcama)</label>
  <button class="alt" onclick="api('costs')">Maliyet raporu</button>
  <button class="alt" onclick="api('contact')">Contact-sheet üret</button>
</div>
<div id="missions"></div>
<h2>Çıktı</h2>
<pre id="out">Hazır. Bir işlem seç.</pre>
<script>
const TOKEN=__TOKEN__;
async function api(action, mission, scene){
  const dry = document.getElementById('dry').checked;
  document.getElementById('out').textContent = '... çalışıyor: '+action+' '+(mission||'')+' '+(scene||'');
  const r = await fetch('/api/run',{method:'POST',headers:{'Content-Type':'application/json','X-Panel-Token':TOKEN},
    body:JSON.stringify({action,mission,scene,dry})});
  const j = await r.json();
  document.getElementById('out').textContent = '[rc='+j.rc+']\\n'+j.out;
}
async function load(){
  const d = await (await fetch('/api/scenes')).json();
  let h='';
  for(const [mid,m] of Object.entries(d)){
    h += '<h2>Mission '+mid+' — '+m.title+'</h2>';
    h += '<div class="row"><button onclick="api(\\'check\\',\\''+mid+'\\')">Doğrula (--check)</button>'+
         '<button class="go" onclick="api(\\'generate\\',\\''+mid+'\\')">Tüm sahneleri üret</button>'+
         '<button class="alt" onclick="api(\\'video\\',\\''+mid+'\\')">Videoya çevir (out/latest)</button></div>';
    h += '<table><tr><th>#</th><th>Başlık</th><th>Kamera</th><th>Lokasyon</th><th></th></tr>';
    for(const s of m.scenes){
      h += '<tr><td>'+s.id+'</td><td>'+s.title+'</td><td>'+s.camera+'</td><td>'+s.location+'</td>'+
           '<td><button onclick="api(\\'generate\\',\\''+mid+'\\',\\''+s.id+'\\')">üret</button></td></tr>';
    }
    h += '</table>';
  }
  document.getElementById('missions').innerHTML = h;
}
load();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/" or path == "/index.html":
            self._send(200, INDEX.replace("__TOKEN__", json.dumps(TOKEN)))
        elif path == "/api/scenes":
            self._send(200, json.dumps(scenes_data(), ensure_ascii=False), "application/json")
        elif path == "/health":
            self._send(200, "ok", "text/plain")
        else:
            self._send(404, "yok")

    def do_POST(self):
        if urlparse(self.path).path != "/api/run":
            return self._send(404, "yok")
        # Token kontrolü — sayfa otomatik gönderir; eksik/yanlışsa reddet.
        if not secrets.compare_digest(self.headers.get("X-Panel-Token", ""), TOKEN):
            return self._send(401, json.dumps({"rc": 1, "out": "yetkisiz (token yok/yanlış)"}),
                              "application/json")
        length = int(self.headers.get("Content-Length", "0"))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._send(400, json.dumps({"rc": 1, "out": "geçersiz istek"}), "application/json")
        cmd = build_cmd(data.get("action", ""), str(data.get("mission", "") or ""),
                        str(data.get("scene", "") or ""), bool(data.get("dry", True)))
        if not cmd:
            return self._send(400, json.dumps({"rc": 1, "out": "bilinmeyen işlem"}), "application/json")
        rc, out = run(cmd)
        self._send(200, json.dumps({"rc": rc, "out": "$ " + " ".join(cmd) + "\n\n" + out},
                                   ensure_ascii=False), "application/json")


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    print(f"NORTH paneli: http://127.0.0.1:{PORT}  (Ctrl+C ile durdur)", file=sys.stderr)
    print(f"  panel token: {TOKEN}  (sabitlemek için PANEL_TOKEN ortam değişkeni)", file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
