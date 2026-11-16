from datetime import datetime
import json
import os
import queue
import threading
import time

import serial
import serial.tools.list_ports
import streamlit as st

HISTORICO_PATH = os.path.join(os.path.dirname(__file__), "historico_dashboard.json")
MAX_HISTORICO_POR_MUSICA = 10

NOMES_MUSICAS = [
    "Axel F",
    "Bad Romance",
    "Beat It",
    "Careless Whisper",
    "Clair de Lune",
    "Clocks",
    "Do Re Mi Fa",
    "Epitafio",
    "Fukashigi No Carte",
    "Fur Elise",
    "Golden",
    "Golden Wind",
    "Harry Potter",
    "Head Over Heels",
    "Hey Jude",
    "Homem Aranha 1900",
    "Imperial March",
    "Interestelar",
    "Korobeiniki (Tetris)",
    "Lugar Ao Sol",
    "Magnetic",
    "Mario Bros",
    "Minecraft (Sweden)",
    "Moonlight Sonata (3rd Mov)",
    "Morning Flower",
    "Never Gonna Give You Up",
    "Numb",
    "Pink Panther",
    "Radio Ga Ga",
    "Sadness And Sorrow",
    "Super Idol",
    "Susanne",
    "Sweet Child O Mine",
    "Take On Me",
    "Trem Das Onze",
    "Undertale (Megalovania)",
    "We Are Number One",
    "When Love Takes Over",
    "Zelda (Lost Woods)",
    "Musica Gravada pelo Usuario",
]


def carregar_historico_disco() -> dict:
    if not os.path.exists(HISTORICO_PATH):
        return {}
    try:
        with open(HISTORICO_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not isinstance(data, dict):
                return {}
            normalizado = {}
            for k, v in data.items():
                if isinstance(v, list):
                    normalizado[str(k)] = v[:MAX_HISTORICO_POR_MUSICA]
                elif isinstance(v, dict) and isinstance(v.get("execucoes"), list):
                    normalizado[str(k)] = list(reversed(v["execucoes"][-MAX_HISTORICO_POR_MUSICA:]))
            return normalizado
    except Exception:
        return {}


def salvar_historico_disco(historico: dict):
    try:
        with open(HISTORICO_PATH, "w", encoding="utf-8") as f:
            json.dump(historico, f, indent=2, ensure_ascii=False)
    except Exception as exc:
        print(f"Erro ao salvar historico: {exc}")


def registrar_execucao(item: dict, historico_por_musica: dict) -> dict:
    chave = str(item.get("musica_id", 0))
    if chave not in historico_por_musica:
        historico_por_musica[chave] = []
    
    registro = {
        "timestamp": item.get("timestamp", datetime.now().strftime("%Y-%m-%d %H:%M:%S")),
        "musica_id": item.get("musica_id", 0),
        "musica": item.get("musica", nome_musica(item.get("musica_id", 0))),
        "acertos": item.get("acertos", 0),
        "erros": item.get("erros", 0),
        "score": item.get("score", 0),
        "total": item.get("total", item.get("acertos", 0) + item.get("erros", 0)),
        "classificacao": item.get("classificacao", classificar_desempenho(item.get("score", 0))),
    }

    historico_por_musica[chave].insert(0, registro)
    historico_por_musica[chave] = historico_por_musica[chave][:MAX_HISTORICO_POR_MUSICA]
    salvar_historico_disco(historico_por_musica)
    return registro


def barra_progresso(score: int, tamanho: int = 30) -> str:
    preenchido = int((score / 100.0) * tamanho)
    barra = "#" * preenchido + "-" * (tamanho - preenchido)
    return f"[{barra}] {score}%"


def classificar_desempenho(score: int) -> str:
    if score >= 95:
        return "Virtuoso! Execucao Perfeita (Rank S)"
    if score >= 85:
        return "Excelente! Otima precisao (Rank A)"
    if score >= 70:
        return "Bom! Poucos deslizes (Rank B)"
    if score >= 50:
        return "Satisfatorio. Continue praticando (Rank C)"
    return "Precisa treinar mais (Rank D)"


def nome_musica(musica_id: int) -> str:
    if 0 <= musica_id < len(NOMES_MUSICAS):
        return NOMES_MUSICAS[musica_id]
    return f"Musica {musica_id}"


def processar_pacote(pacote: bytearray):
    checksum_calc = sum(pacote[1:6]) & 0xFF
    checksum_recv = pacote[6]
    if checksum_calc != checksum_recv:
        return None

    musica_id = pacote[2] & 0x3F
    acertos = pacote[3]
    erros = pacote[4]
    score = pacote[5]
    if (acertos == 0 and erros == 0) or score > 100 or musica_id >= len(NOMES_MUSICAS):
        return None
    return {
        "musica_id": musica_id,
        "musica": nome_musica(musica_id),
        "acertos": acertos,
        "erros": erros,
        "score": score,
        "total": acertos + erros,
        "classificacao": classificar_desempenho(score),
    }


def serial_reader(porta: str, baud: int, stop_event: threading.Event, fila: queue.Queue):
    try:
        ser = serial.Serial(porta, baudrate=baud, timeout=0.05)
    except Exception as exc:  # pragma: no cover - depende do hardware
        fila.put({"erro": f"Nao foi possivel abrir a porta {porta}: {exc}"})
        return

    pacote = bytearray(7)
    estado = 0

    try:
        while not stop_event.is_set():
            b = ser.read(1)
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
                elif val == 0xAA:
                    pacote[0] = val
                    estado = 1
                else:
                    estado = 0
            elif estado in (2, 3, 4, 5):
                pacote[estado] = val
                estado += 1
            elif estado == 6:
                pacote[6] = val
                estado = 0
                resultado = processar_pacote(pacote)
                if resultado is not None:
                    fila.put(resultado)
    finally:
        ser.close()


def listar_portas():
    portas = list(serial.tools.list_ports.comports())
    return [p.device for p in portas]


def encerrar_conexao_serial():
    if st.session_state.stop_event is not None:
        st.session_state.stop_event.set()
    if st.session_state.thread is not None:
        st.session_state.thread.join(timeout=0.2)
    st.session_state.conectado = False
    st.session_state.thread = None
    st.session_state.stop_event = None


def demo_resultados():
    return [
        {
            "musica_id": 6,
            "musica": "Do Re Mi Fa",
            "acertos": 7,
            "erros": 1,
            "score": 87,
            "total": 8,
            "classificacao": "Excelente! Otima precisao (Rank A)",
        },
        {
            "musica_id": 4,
            "musica": "Clair de Lune",
            "acertos": 42,
            "erros": 3,
            "score": 93,
            "total": 45,
            "classificacao": "Excelente! Otima precisao (Rank A)",
        },
    ]


st.set_page_config(page_title="Dashboard Piano FPGA", layout="wide")
st.title("Dashboard do Piano FPGA")
st.caption("Monitor do modo aprendizado em tempo real")

if "historico_por_musica" not in st.session_state:
    st.session_state.historico_por_musica = carregar_historico_disco()
if "ultimo_resultado" not in st.session_state:
    st.session_state.ultimo_resultado = None
if "porta" not in st.session_state:
    st.session_state.porta = ""
if "baud" not in st.session_state:
    st.session_state.baud = 115200
if "conectado" not in st.session_state:
    st.session_state.conectado = False
if "thread" not in st.session_state:
    st.session_state.thread = None
if "stop_event" not in st.session_state:
    st.session_state.stop_event = None
if "fila" not in st.session_state:
    st.session_state.fila = None

with st.sidebar:
    st.header("Configuração")
    portas = listar_portas()
    porta_selecionada = st.selectbox("Porta serial", portas if portas else ["Nenhuma porta detectada"], index=0)
    st.session_state.porta = porta_selecionada
    st.session_state.baud = st.number_input("Baud rate", min_value=9600, max_value=230400, value=115200, step=9600)

    col1, col2 = st.columns(2)
    with col1:
        if st.button("Conectar") and portas:
            if st.session_state.thread and st.session_state.thread.is_alive():
                st.warning("Já existe uma conexão ativa.")
            else:
                fila = queue.Queue()
                stop_event = threading.Event()
                thread = threading.Thread(
                    target=serial_reader,
                    args=(st.session_state.porta, st.session_state.baud, stop_event, fila),
                    daemon=True,
                )
                thread.start()
                st.session_state.fila = fila
                st.session_state.stop_event = stop_event
                st.session_state.thread = thread
                st.session_state.conectado = True
                st.success(f"Conectado em {st.session_state.porta}")
    with col2:
        if st.button("Desconectar"):
            encerrar_conexao_serial()
            st.success("Conexão encerrada.")

    if st.button("Carregar demo"):
        encerrar_conexao_serial()
        for demo in demo_resultados():
            res = registrar_execucao(demo, st.session_state.historico_por_musica)
            st.session_state.ultimo_resultado = res
        st.success("Dados de demonstração inseridos!")

if st.session_state.fila is not None:
    while not st.session_state.fila.empty():
        dado = st.session_state.fila.get()
        if "erro" in dado:
            st.error(dado["erro"])
            encerrar_conexao_serial()
        else:
            res = registrar_execucao(dado, st.session_state.historico_por_musica)
            st.session_state.ultimo_resultado = res
    if not st.session_state.conectado:
        st.session_state.fila = None

if st.session_state.ultimo_resultado is not None:
    ultimo = st.session_state.ultimo_resultado
    st.subheader(f"Última Execução: {ultimo['musica']}")

    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Acertos", ultimo["acertos"])
    col2.metric("Erros", ultimo["erros"])
    col3.metric("Score", f"{ultimo['score']}%")
    col4.metric("Total", ultimo["total"])

    barra = barra_progresso(ultimo["score"])
    st.markdown(f"**Aproveitamento Final:** {barra}")
    st.markdown(f"**Classificação:** {ultimo['classificacao']}")
    st.progress(min(max(ultimo["score"], 0), 100) / 100)
else:
    st.info("Aguardando dados. Conecte a FPGA ou carregue a demonstração.")

st.markdown("---")
st.subheader("Histórico Individual por Música (Últimas 10 execuções)")

musicas_com_historico = [
    int(k) for k in st.session_state.historico_por_musica.keys() if st.session_state.historico_por_musica[k]
]

if musicas_com_historico:
    opcoes_musica = sorted(musicas_com_historico)
    idx_default = 0
    if st.session_state.ultimo_resultado is not None:
        ultimo_id = st.session_state.ultimo_resultado.get("musica_id")
        if ultimo_id in opcoes_musica:
            idx_default = opcoes_musica.index(ultimo_id)

    musica_sel_id = st.selectbox(
        "Selecione a música para ver o histórico:",
        opcoes_musica,
        index=idx_default,
        format_func=lambda mid: f"{mid:02d} - {nome_musica(mid)} ({len(st.session_state.historico_por_musica[str(mid)])} execuções)",
    )

    lista_execucoes = st.session_state.historico_por_musica.get(str(musica_sel_id), [])

    if lista_execucoes:
        # Gráfico das últimas execuções
        scores_rev = [item.get("score", 0) for item in reversed(lista_execucoes)]
        st.caption("Evolução dos scores nas últimas execuções:")
        st.bar_chart(scores_rev)

        tabela_df = [
            {
                "#": idx + 1,
                "Data/Hora": item.get("timestamp", "-"),
                "Música": item.get("musica", nome_musica(musica_sel_id)),
                "Acertos": item.get("acertos", 0),
                "Erros": item.get("erros", 0),
                "Score": f"{item.get('score', 0)}%",
                "Classificação": item.get("classificacao", classificar_desempenho(item.get("score", 0))),
            }
            for idx, item in enumerate(lista_execucoes)
        ]
        st.dataframe(tabela_df, use_container_width=True)
else:
    st.caption("Nenhum histórico registrado ainda. Execute uma música no Piano FPGA ou carregue a demo.")

if not portas:
    st.warning("Nenhuma porta serial detectada no computador.")

if st.session_state.conectado:
    if st.session_state.thread is None or not st.session_state.thread.is_alive():
        encerrar_conexao_serial()
        st.session_state.fila = None
    else:
        time.sleep(0.5)
        st.rerun()
