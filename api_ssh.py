#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import os, json, subprocess, datetime

PORT = 8080

class SSHAPI(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

    def do_GET(self):
        if self.path == "/usuarios":
            usuarios = subprocess.getoutput("awk -F: '$3 >= 1000 && $1 != \"nobody\" {print $1}' /etc/passwd").splitlines()
            data = {"usuarios_ativos": usuarios}
        elif self.path == "/logins":
            logins = subprocess.getoutput("ss -o state established '( dport = :ssh )' | awk '/ESTAB/ {print $6}' | cut -d':' -f1 | sort | uniq -c")
            data = {"logins_ativos": logins}
        elif self.path == "/relatorio":
            relatorio = subprocess.getoutput("tail -n 10 /var/log/ssh_manager.log")
            data = {"ultimos_eventos": relatorio.splitlines()}
        else:
            data = {"erro": "endpoint inválido"}

        self._set_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())

if __name__ == "__main__":
    print(f"API SSH rodando em http://0.0.0.0:{PORT}")
    HTTPServer(("", PORT), SSHAPI).serve_forever()
