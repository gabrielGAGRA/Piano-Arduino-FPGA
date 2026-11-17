#!/usr/bin/env python3
"""
Dashboard do Modo Aprendizado - Piano FPGA (DE0-CV).

Interface Web moderna e CLI com suporte a:
- Visualizacao grafica interativa no navegador (http://localhost:8000)
- Conexao direta com a FPGA via Web Serial (Chrome/Edge) ou porta COM local
- Historico individual das 10 ultimas execucoes por melodia (historico_dashboard.json)
"""

import argparse
import http.server


import json
import os
from pathlib import Path
import socketserver
import sys
import threading
import time
import urllib.parse
import webbrowser

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None

NOMES_MUSICAS = [
    "Axel F",                     # 0
    "Bad Romance",                # 1
    "Beat It",                    # 2
    "Careless Whisper",           # 3
    "Clair de Lune",              # 4
    "Clocks",                     # 5
    "Do Re Mi Fa",                # 6
    "Epitafio",                   # 7
    "Fukashigi No Carte",         # 8
    "Fur Elise",                  # 9
    "Golden",                     # 10
    "Golden Wind",                # 11
    "Harry Potter",               # 12
    "Head Over Heels",            # 13
    "Hey Jude",                   # 14
    "Homem Aranha 1900",          # 15
    "Imperial March",             # 16
    "Interestelar",               # 17
    "Jump Up Super Star",         # 18
    "Korobeiniki (Tetris)",       # 19
    "Lugar Ao Sol",               # 20
    "Magnetic",                   # 21
    "Mario Bros",                 # 22
    "Minecraft (Sweden)",         # 23
    "Moonlight Sonata (3rd Mov)", # 24
    "Morning Flower",             # 25
    "Never Gonna Give You Up",    # 26
    "New Donk City",              # 27
    "Numb",                       # 28
    "Pink Panther",               # 29
    "Radio Ga Ga",                # 30
    "Sadness And Sorrow",         # 31
    "Super Idol",                 # 32
    "Susanne",                    # 33
    "Sweet Child O Mine",         # 34
    "Take On Me",                 # 35
    "Trem Das Onze",              # 36
    "Undertale (Megalovania)",    # 37
    "We Are Number One",          # 38
    "When Love Takes Over",       # 39
    "Wii Sports",                 # 40
    "Zelda (Lost Woods)",         # 41
    "Musica Gravada pelo Usuario" # 42
]

SCRIPTS_DIR = Path(__file__).resolve().parent
DEFAULT_HISTORY_FILE = SCRIPTS_DIR / "historico_dashboard.json"
HTML_FILE = SCRIPTS_DIR / "dashboard.html"
MAX_EXECUCOES_POR_MUSICA = 10


def barra_progresso(score: int, tamanho: int = 30) -> str:
    preenchido = int((score / 100.0) * tamanho)
    barra = "#" * preenchido + "-" * (tamanho - preenchido)
    return f"[{barra}] {score}%"


def classificar_desempenho(score: int) -> str:
    if score >= 95:
        return "Virtuoso! Execucao Perfeita (Rank S)"
    elif score >= 85:
        return "Excelente! Otima precisao (Rank A)"
    elif score >= 70:
        return "Bom! Poucos deslizes (Rank B)"
    elif score >= 50:
        return "Satisfatorio. Continue praticando (Rank C)"
    else:
        return "Precisa treinar mais (Rank D)"


def carregar_historico(history_file=DEFAULT_HISTORY_FILE) -> dict:
    path = Path(history_file)
    if not path.is_file():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not isinstance(data, dict):
                return {}
            normalizado = {}
            for k, v in data.items():
                if isinstance(v, list):
                    mid = int(k) if str(k).isdigit() else 0
                    nome = NOMES_MUSICAS[mid] if 0 <= mid < len(NOMES_MUSICAS) else f"Musica {mid}"
                    normalizado[str(k)] = {
                        "musica_id": mid,
                        "nome": nome,
                        "execucoes": list(reversed(v[:MAX_EXECUCOES_POR_MUSICA])),
                    }
                elif isinstance(v, dict):
                    normalizado[str(k)] = v
            return normalizado
    except (json.JSONDecodeError, OSError):
        return {}


def salvar_historico(historico: dict, history_file=DEFAULT_HISTORY_FILE):
    path = Path(history_file)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(historico, f, indent=2, ensure_ascii=False)
    except OSError as e:
        print(f"[AVISO] Nao foi possivel salvar historico em {path}: {e}")


def registrar_execucao(
    musica_id: int,
    acertos: int,
    erros: int,
    score: int,
    historico: dict = None,
    history_file=DEFAULT_HISTORY_FILE,
    timestamp: str = None
) -> dict:
    if historico is None:
        historico = carregar_historico(history_file)

    key = str(musica_id)
    nome_musica = NOMES_MUSICAS[musica_id] if musica_id < len(NOMES_MUSICAS) else f"Musica {musica_id}"
    total = acertos + erros
    ts = timestamp if timestamp else time.strftime("%Y-%m-%d %H:%M:%S")

    nova_execucao = {
        "timestamp": ts,
        "acertos": acertos,
        "erros": erros,
        "total": total,
        "score": score
    }

    if key not in historico or not isinstance(historico[key], dict):
        historico[key] = {
            "musica_id": musica_id,
            "nome": nome_musica,
            "execucoes": []
        }

    execucoes = historico[key].get("execucoes", [])
    if not isinstance(execucoes, list):
        execucoes = []

    execucoes.append(nova_execucao)
    if len(execucoes) > MAX_EXECUCOES_POR_MUSICA:
        execucoes = execucoes[-MAX_EXECUCOES_POR_MUSICA:]

    historico[key]["execucoes"] = execucoes
    historico[key]["nome"] = nome_musica

    if history_file:
        salvar_historico(historico, history_file)

    return historico


def exibir_tabela_historico(musica_id: int, historico: dict):
    key = str(musica_id)
    if key not in historico or not historico[key].get("execucoes"):
        return

    entry = historico[key]
    execucoes = entry["execucoes"]
    nome_musica = entry.get("nome", f"Musica {musica_id}")

    print(f"--- Ultimas Execucoes Salvas: #{musica_id:02d} ({nome_musica}) ---")
    print(" N   | Data/Hora           | Acertos | Erros | Total | Score")
    print("-" * 65)
    scores = []
    for idx, ex in enumerate(execucoes, start=1):
        ts = ex.get("timestamp", "-")
        ac = ex.get("acertos", 0)
        er = ex.get("erros", 0)
        tot = ex.get("total", ac + er)
        sc = ex.get("score", 0)
        scores.append(sc)
        print(f" {idx:2d}  | {ts:19s} | {ac:7d} | {er:5d} | {tot:5d} | {sc:4d}%")

    if scores:
        media = sum(scores) / len(scores)
        melhor = max(scores)
        print("-" * 65)
        print(f" Melhores: {melhor}% | Media das ultimas {len(scores)} partidas: {media:.1f}%\n")


def exibir_resumo_todas_musicas(historico: dict):
    if not historico:
        print("\nNenhuma execucao salva no historico.")
        return

    print("\n" + "=" * 65)
    print("           HISTORICO GERAL - MODO APRENDIZADO")
    print("=" * 65)
    print(" ID | Musica                       | Partidas | Ultimo | Melhor")
    print("-" * 65)

    chaves_ordenadas = sorted(historico.keys(), key=lambda k: int(k) if k.isdigit() else 999)
    for k in chaves_ordenadas:
        item = historico[k]
        mid = item.get("musica_id", int(k) if k.isdigit() else 0)
        nome = item.get("nome", f"Musica {mid}")
        execs = item.get("execucoes", [])
        if not execs:
            continue
        qtd = len(execs)
        ultimo = execs[-1].get("score", 0)
        melhor = max(e.get("score", 0) for e in execs)
        print(f" {mid:02d} | {nome:28s} | {qtd:8d} | {ultimo:5d}% | {melhor:5d}%")
    print("=" * 65 + "\n")


def exibir_dashboard(musica_id: int, acertos: int, erros: int, score: int, historico: dict = None):
    nome_musica = NOMES_MUSICAS[musica_id] if musica_id < len(NOMES_MUSICAS) else f"Musica {musica_id}"
    total = acertos + erros
    hora = time.strftime("%H:%M:%S")

    print("\n" + "=" * 65)
    print(f"         DASHBOARD DE DESEMPENHO - MODO APRENDIZADO [{hora}]")
    print("=" * 65)
    print(f" Melodia : #{musica_id:02d} - {nome_musica}")
    print(f" Total de Tentativas : {total}")
    print(f" Notas Corretas      : {acertos}  ({(acertos/total*100) if total else 0:.1f}%)")
    print(f" Notas Erradas       : {erros}  ({(erros/total*100) if total else 0:.1f}%)")
    print("-" * 65)
    print(f" Aproveitamento Final: {barra_progresso(score)}")
    print(f" Avaliacao           : {classificar_desempenho(score)}")
    print("=" * 65)

    if historico:
        exibir_tabela_historico(musica_id, historico)


def processar_stream(porta_serial, history_file=DEFAULT_HISTORY_FILE):
    print(f"[*] Aguardando dados da FPGA na porta {porta_serial.port} (115200 bps)...")
    print(f"[*] Historico das 10 ultimas execucoes por musica: {history_file}\n")

    historico = carregar_historico(history_file)
    estado = 0
    pacote = bytearray(7)

    while True:
        try:
            b = porta_serial.read(1)
            if not b:
                continue
            val = b[0]

            if estado == 0:
                if val == 0xAA:
                    pacote[0] = val
                    estado = 1
            elif estado == 1:
                if val == 0xD1:
                    pacote[1] = val
                    estado = 2
                else:
                    estado = 0
            elif estado in (2, 3, 4, 5):
                pacote[estado] = val
                estado += 1
            elif estado == 6:
                pacote[6] = val
                estado = 0

                checksum_calc = sum(pacote[1:6]) & 0xFF
                checksum_recv = pacote[6]

                if checksum_calc == checksum_recv:
                    musica_id = pacote[2] & 0x3F
                    acertos = pacote[3]
                    erros = pacote[4]
                    score = pacote[5]

                    historico = registrar_execucao(
                        musica_id=musica_id,
                        acertos=acertos,
                        erros=erros,
                        score=score,
                        historico=historico,
                        history_file=history_file
                    )
                    exibir_dashboard(musica_id, acertos, erros, score, historico)
                else:
                    print(f"[!] Erro de Checksum: calculado 0x{checksum_calc:02X}, recebido 0x{checksum_recv:02X}")
        except Exception:
            break


def criar_http_handler(history_path):
    class DashboardHTTPHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path in ("/", "/index.html", "/dashboard.html"):
                if HTML_FILE.is_file():
                    content = HTML_FILE.read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(content)))
                    self.end_headers()
                    self.wfile.write(content)
                else:
                    self.send_error(404, "Arquivo HTML do dashboard nao encontrado.")
            elif parsed.path == "/api/history":
                data = carregar_historico(history_path)
                body = json.dumps(data, ensure_ascii=False).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_error(404, "Not Found")

        def do_POST(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/api/record":
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                try:
                    payload = json.loads(body.decode("utf-8"))
                    mid = int(payload.get("musica_id", 0))
                    ac = int(payload.get("acertos", 0))
                    er = int(payload.get("erros", 0))
                    sc = int(payload.get("score", 0))
                    registrar_execucao(mid, ac, er, sc, history_file=history_path)

                    resp = b'{"status": "ok"}'
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.send_header("Content-Length", str(len(resp)))
                    self.end_headers()
                    self.wfile.write(resp)
                except Exception as e:
                    self.send_error(400, f"JSON invalido: {e}")
            else:
                self.send_error(404, "Not Found")

    return DashboardHTTPHandler


def iniciar_servidor_web(history_path, porta_http=8000, abrir_navegador=True, serial_port=None, baud=115200):
    handler = criar_http_handler(history_path)

    # Thread para escuta serial em segundo plano se houver porta COM
    if serial and serial_port:
        try:
            ser = serial.Serial(serial_port, baudrate=baud, timeout=1.0)
            t_serial = threading.Thread(target=processar_stream, args=(ser, history_path), daemon=True)
            t_serial.start()
            print(f"[*] Escutando dados da FPGA em {serial_port} a {baud} bps...")
        except Exception as e:
            print(f"[AVISO] Nao foi possivel abrir a porta serial {serial_port}: {e}")

    url = f"http://localhost:{porta_http}"
    print("\n" + "=" * 65)
    print(f"      🎹 DASHBOARD WEB PIANO FPGA INICIADA COM SUCESSO")
    print("=" * 65)
    print(f" URL Local : {url}")
    print(f" Historico : {history_path}")
    print(" Pressione Ctrl+C para encerrar o servidor.")
    print("=" * 65 + "\n")

    if abrir_navegador:
        try:
            webbrowser.open(url)
        except Exception:
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    with ReusableTCPServer(("", porta_http), handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[Servidor Web encerrado]")


def listar_portas():
    if not serial:
        return None
    portas = list(serial.tools.list_ports.comports())
    return portas


def main():
    parser = argparse.ArgumentParser(description="Dashboard Web e PC para Piano FPGA DE0-CV")
    parser.add_argument("-p", "--port", help="Porta serial (ex: COM3 ou /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate (padrao: 115200)")
    parser.add_argument("--web-port", type=int, default=8000, help="Porta HTTP do Dashboard Web (padrao: 8000)")
    parser.add_argument("--cli", action="store_true", help="Executa exclusivamente no modo terminal (sem abrir navegador)")
    parser.add_argument("--no-browser", action="store_true", help="Inicia o servidor web mas nao abre o navegador automaticamente")
    parser.add_argument("--demo", action="store_true", help="Executa demonstracao com dados ficticios")
    parser.add_argument(
        "--historico",
        nargs="?",
        const="all",
        help="Exibe historico salvo de uma musica (--historico ID) ou de todas (--historico)"
    )
    parser.add_argument(
        "--history-file",
        default=str(DEFAULT_HISTORY_FILE),
        help=f"Arquivo JSON para historico (padrao: {DEFAULT_HISTORY_FILE})"
    )

    args = parser.parse_args()
    history_path = Path(args.history_file)

    if args.historico is not None:
        historico = carregar_historico(history_path)
        if args.historico == "all":
            exibir_resumo_todas_musicas(historico)
        else:
            try:
                mid = int(args.historico)
                exibir_tabela_historico(mid, historico)
            except ValueError:
                print(f"[ERRO] ID de musica invalido: {args.historico}")
        return

    if args.demo:
        print("[*] Modo Demonstracao Terminal:")
        exibir_dashboard(musica_id=6, acertos=7, erros=1, score=87)
        exibir_dashboard(musica_id=4, acertos=42, erros=3, score=93)
        return

    # Se o usuario solicitou modo CLI puro
    if args.cli:
        if not serial:
            print("[ERRO] Biblioteca 'pyserial' nao encontrada.")
            sys.exit(1)
        porta = args.port
        if not porta:
            portas = listar_portas()
            if not portas:
                print("Nenhuma porta serial detectada no computador.")
                sys.exit(1)
            porta = portas[0].device
            print(f"Porta selecionada: {porta}")

        try:
            ser = serial.Serial(porta, baudrate=args.baud, timeout=1.0)
            processar_stream(ser, history_file=history_path)
        except Exception as e:
            print(f"[ERRO] {e}")
        return

    # Modo Padrao: Inicia o Dashboard Web e abre o navegador
    porta_serial = args.port
    if not porta_serial and serial:
        portas = listar_portas()
        if portas:
            porta_serial = portas[0].device

    iniciar_servidor_web(
        history_path=history_path,
        porta_http=args.web_port,
        abrir_navegador=(not args.no_browser),
        serial_port=porta_serial,
        baud=args.baud
    )


if __name__ == "__main__":
    main()
