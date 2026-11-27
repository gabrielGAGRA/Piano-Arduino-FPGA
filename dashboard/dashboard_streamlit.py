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
    "Jump Up Super Star",
    "Korobeiniki (Tetris)",
    "Lugar Ao Sol",
    "Magnetic",
    "Mario Bros",
    "Minecraft (Sweden)",
    "Moonlight Sonata (3rd Mov)",
    "Morning Flower",
    "Never Gonna Give You Up",
    "New Donk City",
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
    "Wii Sports",
    "Zelda (Lost Woods)",
    "Musica Gravada pelo Usuario",
]


def calcular_estatisticas_musica(execucoes: list) -> dict:
    if not execucoes:
        return {
            "total_execucoes": 0,
            "media_score": 0.0,
            "melhor_score": 0,
            "pior_score": 0,
            "ultimo_score": 0,
            "tendencia": 0.0,
            "total_acertos": 0,
            "total_erros": 0,
            "taxa_acerto_media": 0.0,
            "melhor_classificacao": "-",
        }

    scores = [int(item.get("score", 0)) for item in execucoes]
    total_acertos = sum(int(item.get("acertos", 0)) for item in execucoes)
    total_erros = sum(int(item.get("erros", 0)) for item in execucoes)
    total_notas = total_acertos + total_erros
    media_score = round(sum(scores) / len(scores), 1)
    melhor_score = max(scores)
    pior_score = min(scores)
    ultimo_score = scores[0]
    if len(scores) > 1:
        media_anteriores = sum(scores[1:]) / len(scores[1:])
        tendencia = round(ultimo_score - media_anteriores, 1)
    else:
        tendencia = 0.0

    taxa_acerto = round((total_acertos / total_notas) * 100.0, 1) if total_notas > 0 else 0.0

    return {
        "total_execucoes": len(execucoes),
        "media_score": media_score,
        "melhor_score": melhor_score,
        "pior_score": pior_score,
        "ultimo_score": ultimo_score,
        "tendencia": tendencia,
        "total_acertos": total_acertos,
        "total_erros": total_erros,
        "taxa_acerto_media": taxa_acerto,
        "melhor_classificacao": classificar_desempenho(melhor_score),
    }


def calcular_estatisticas_gerais(historico_por_musica: dict) -> dict:
    todas_execucoes = []
    musicas_praticadas = 0
    for execucoes in historico_por_musica.values():
        if execucoes:
            musicas_praticadas += 1
            todas_execucoes.extend(execucoes)

    if not todas_execucoes:
        return {
            "musicas_praticadas": 0,
            "total_execucoes": 0,
            "media_geral": 0.0,
            "melhor_score_geral": 0,
        }

    scores = [int(item.get("score", 0)) for item in todas_execucoes]
    return {
        "musicas_praticadas": musicas_praticadas,
        "total_execucoes": len(todas_execucoes),
        "media_geral": round(sum(scores) / len(scores), 1),
        "melhor_score_geral": max(scores),
    }


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
                    execucoes = v["execucoes"]
                    if len(execucoes) >= 2 and str(execucoes[0].get("timestamp", "")) < str(execucoes[-1].get("timestamp", "")):
                        execucoes = list(reversed(execucoes))
                    normalizado[str(k)] = execucoes[:MAX_HISTORICO_POR_MUSICA]
            return normalizado
    except Exception:
        return {}


def salvar_historico_disco(historico: dict):
    try:
        payload = {}
        for chave, execucoes in historico.items():
            if not execucoes:
                continue
            try:
                musica_id = int(chave)
            except ValueError:
                musica_id = execucoes[0].get("musica_id", 0)
            payload[str(chave)] = {
                "musica_id": musica_id,
                "musica": execucoes[0].get("musica", nome_musica(musica_id)),
                "estatisticas": calcular_estatisticas_musica(execucoes),
                "execucoes": execucoes[:MAX_HISTORICO_POR_MUSICA],
            }
        with open(HISTORICO_PATH, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
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


def aplicar_tema_personalizado():
    # SVG sutil com pecas de quebra-cabeca em azul claro e tons pasteis suaves (simbolo do autismo)
    puzzle_svg = (
        "<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220' viewBox='0 0 220 220'>"
        "<g fill='none' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'>"
        "<path d='M26 26 h18 a6 6 0 1 1 12 0 h18 v18 a6 6 0 1 1 0 12 v18 h-18 a6 6 0 1 0 -12 0 h-18 v-18 a6 6 0 1 0 0 -12 z' "
        "fill='#5FA8D3' fill-opacity='0.065' stroke='#5FA8D3' stroke-opacity='0.14'/>"
        "<path d='M132 34 h16 a5.5 5.5 0 1 0 11 0 h16 v16 a5.5 5.5 0 1 1 0 11 v16 h-16 a5.5 5.5 0 1 1 -11 0 h-16 v-16 a5.5 5.5 0 1 0 0 -11 z' "
        "fill='#62B6CB' fill-opacity='0.055' stroke='#62B6CB' stroke-opacity='0.13' transform='rotate(14 153 55)'/>"
        "<path d='M36 136 h16 a5.5 5.5 0 1 1 11 0 h16 v16 a5.5 5.5 0 1 0 0 11 v16 h-16 a5.5 5.5 0 1 0 -11 0 h-16 v-16 a5.5 5.5 0 1 1 0 -11 z' "
        "fill='#F4A261' fill-opacity='0.05' stroke='#F4A261' stroke-opacity='0.11' transform='rotate(-12 57 157)'/>"
        "<path d='M134 134 h18 a6 6 0 1 0 12 0 h18 v18 a6 6 0 1 1 0 12 v18 h-18 a6 6 0 1 1 -12 0 h-18 v-18 a6 6 0 1 0 0 -12 z' "
        "fill='#4EA8DE' fill-opacity='0.06' stroke='#4EA8DE' stroke-opacity='0.13' transform='rotate(8 158 158)'/>"
        "</g>"
        "</svg>"
    )
    puzzle_uri = "data:image/svg+xml;utf8," + puzzle_svg.replace("#", "%23").replace(" ", "%20")

    st.markdown(
        f"""
        <style>
        .stApp {{
            background-color: #EFF7FD;
            background-image:
                url("{puzzle_uri}"),
                linear-gradient(160deg, #F4FAFF 0%, #E7F3FC 55%, #EEF8FA 100%);
            background-repeat: repeat, no-repeat;
            background-size: 220px 220px, cover;
            color: #1B3A4B;
        }}

        [data-testid="stHeader"] {{
            background: rgba(239, 247, 253, 0.72);
            backdrop-filter: blur(8px);
        }}

        [data-testid="stSidebar"] {{
            background: linear-gradient(180deg, #E1F0FA 0%, #EDF6FC 100%);
            border-right: 1px solid #C8E1F2;
        }}

        [data-testid="stSidebar"] h1,
        [data-testid="stSidebar"] h2,
        [data-testid="stSidebar"] h3,
        .stApp h1, .stApp h2, .stApp h3 {{
            color: #163A52;
        }}

        [data-testid="stSidebar"] label,
        [data-testid="stSidebar"] p,
        [data-testid="stSidebar"] [data-testid="stCaptionContainer"],
        .stApp [data-testid="stWidgetLabel"] p,
        .stApp [data-testid="stCaptionContainer"] {{
            color: #244961 !important;
        }}

        .hero-card {{
            background: linear-gradient(135deg, rgba(255, 255, 255, 0.92) 0%, rgba(227, 242, 253, 0.92) 100%);
            border: 1px solid #C5E0F5;
            border-left: 6px solid #4EA8DE;
            border-radius: 16px;
            padding: 1.25rem 1.5rem;
            margin-bottom: 1.2rem;
            box-shadow: 0 6px 20px rgba(78, 168, 222, 0.10);
        }}

        .hero-title {{
            font-size: 1.85rem;
            font-weight: 700;
            color: #153B54;
            margin: 0 0 0.25rem 0;
            letter-spacing: -0.01em;
        }}

        .hero-subtitle {{
            font-size: 0.98rem;
            color: #3D627A;
            margin: 0;
        }}

        .status-pill {{
            display: inline-block;
            padding: 0.3rem 0.75rem;
            border-radius: 999px;
            font-size: 0.82rem;
            font-weight: 600;
            margin-bottom: 0.75rem;
        }}

        .status-online {{
            background-color: #D8F3DC;
            color: #1B4332;
            border: 1px solid #95D5B2;
        }}

        .status-offline {{
            background-color: #E3EFF8;
            color: #3D5A73;
            border: 1px solid #BDD7EB;
        }}

        .rank-banner {{
            background: rgba(255, 255, 255, 0.88);
            border: 1px solid #CBE2F3;
            border-radius: 12px;
            padding: 0.85rem 1.1rem;
            margin: 0.5rem 0 0.9rem 0;
            color: #1B3A4B;
        }}

        [data-testid="stMetric"] {{
            background: rgba(255, 255, 255, 0.88);
            border: 1px solid #CFE3F4;
            border-radius: 14px;
            padding: 0.9rem 1rem;
            box-shadow: 0 3px 12px rgba(44, 98, 138, 0.06);
        }}

        [data-testid="stMetricLabel"] {{
            color: #466B85 !important;
            font-weight: 600 !important;
        }}

        [data-testid="stMetricValue"] {{
            color: #153B54 !important;
        }}

        .stButton > button {{
            background-color: #5FA8D3;
            color: #FFFFFF;
            border: none;
            border-radius: 10px;
            font-weight: 600;
            transition: background-color 0.2s ease, transform 0.1s ease;
        }}

        .stButton > button:hover {{
            background-color: #4895C4;
            color: #FFFFFF;
        }}

        [data-testid="stProgress"] > div > div > div > div {{
            background: linear-gradient(90deg, #5FA8D3 0%, #62B6CB 60%, #2A9D8F 100%);
        }}

        [data-testid="stDataFrame"] {{
            background: rgba(255, 255, 255, 0.92);
            border-radius: 12px;
            padding: 0.25rem;
            border: 1px solid #CFE3F4;
        }}
        </style>
        """,
        unsafe_allow_html=True,
    )


st.set_page_config(page_title="Dashboard Piano FPGA", page_icon="🎹", layout="wide")
aplicar_tema_personalizado()

st.markdown(
    """
    <div class="hero-card">
        <div class="hero-title">Dashboard do Piano FPGA</div>
        <p class="hero-subtitle">Acompanhamento sensorial e musical do modo aprendizado em tempo real</p>
    </div>
    """,
    unsafe_allow_html=True,
)

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
    st.header("Conexão e Controle")
    if st.session_state.conectado:
        st.markdown(
            f'<div class="status-pill status-online">Conectado ({st.session_state.porta})</div>',
            unsafe_allow_html=True,
        )
    else:
        st.markdown(
            '<div class="status-pill status-offline">Aguardando conexão</div>',
            unsafe_allow_html=True,
        )

    portas = listar_portas()
    porta_selecionada = st.selectbox("Porta serial", portas if portas else ["Nenhuma porta detectada"], index=0)
    st.session_state.porta = porta_selecionada
    st.session_state.baud = st.number_input("Baud rate", min_value=9600, max_value=230400, value=115200, step=9600)

    col1, col2 = st.columns(2)
    with col1:
        if st.button("Conectar", width="stretch") and portas:
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
        if st.button("Desconectar", width="stretch"):
            encerrar_conexao_serial()
            st.success("Conexão encerrada.")

    st.markdown("---")
    if st.button("Carregar demo", width="stretch"):
        encerrar_conexao_serial()
        for demo in demo_resultados():
            res = registrar_execucao(demo, st.session_state.historico_por_musica)
            st.session_state.ultimo_resultado = res
        st.success("Dados de demonstração inseridos!")

    if st.button("Limpar histórico", width="stretch"):
        st.session_state.historico_por_musica = {}
        st.session_state.ultimo_resultado = None
        salvar_historico_disco({})
        st.info("Histórico limpo.")

    st.caption(f"Persistência: `{os.path.basename(HISTORICO_PATH)}` (até {MAX_HISTORICO_POR_MUSICA} execuções por música)")

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
    col4.metric("Total de Notas", ultimo["total"])

    st.markdown(
        f"""
        <div class="rank-banner">
            <strong>Classificação:</strong> {ultimo['classificacao']}<br/>
            <strong>Aproveitamento Final:</strong> {ultimo['score']}%
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.progress(min(max(ultimo["score"], 0), 100) / 100)
else:
    st.info("Aguardando dados. Conecte a FPGA ou carregue a demonstração na barra lateral.")

st.markdown("---")
st.subheader("Estatísticas e Histórico por Música (Últimas 10 execuções)")

musicas_com_historico = [
    int(k) for k in st.session_state.historico_por_musica.keys() if st.session_state.historico_por_musica[k]
]

if musicas_com_historico:
    stats_gerais = calcular_estatisticas_gerais(st.session_state.historico_por_musica)
    g1, g2, g3, g4 = st.columns(4)
    g1.metric("Músicas Praticadas", stats_gerais["musicas_praticadas"])
    g2.metric("Execuções Salvas", stats_gerais["total_execucoes"])
    g3.metric("Média Geral", f"{stats_gerais['media_geral']}%")
    g4.metric("Recorde Geral", f"{stats_gerais['melhor_score_geral']}%")

    opcoes_musica = sorted(musicas_com_historico)
    idx_default = 0
    if st.session_state.ultimo_resultado is not None:
        ultimo_id = st.session_state.ultimo_resultado.get("musica_id")
        if ultimo_id in opcoes_musica:
            idx_default = opcoes_musica.index(ultimo_id)

    musica_sel_id = st.selectbox(
        "Selecione a música para ver estatísticas e histórico:",
        opcoes_musica,
        index=idx_default,
        format_func=lambda mid: f"{mid:02d} - {nome_musica(mid)} ({len(st.session_state.historico_por_musica[str(mid)])} execuções)",
    )

    lista_execucoes = st.session_state.historico_por_musica.get(str(musica_sel_id), [])

    if lista_execucoes:
        stats_musica = calcular_estatisticas_musica(lista_execucoes)
        tendencia = stats_musica["tendencia"]
        delta_str = f"{tendencia:+.1f}% vs média anterior" if len(lista_execucoes) > 1 else None

        m1, m2, m3, m4 = st.columns(4)
        m1.metric("Execuções (máx. 10)", stats_musica["total_execucoes"])
        m2.metric("Média da Música", f"{stats_musica['media_score']}%", delta=delta_str)
        m3.metric("Melhor Score", f"{stats_musica['melhor_score']}%")
        m4.metric("Taxa de Acerto", f"{stats_musica['taxa_acerto_media']}%")

        st.caption(
            f"Resumo acumulado da janela: {stats_musica['total_acertos']} acertos, "
            f"{stats_musica['total_erros']} erros | Melhor nível: {stats_musica['melhor_classificacao']}"
        )

        # Gráfico das últimas execuções em ordem cronológica (mais antiga -> mais recente)
        scores_rev = [item.get("score", 0) for item in reversed(lista_execucoes)]
        st.caption("Evolução dos scores nas últimas execuções:")
        st.bar_chart(scores_rev, color="#5FA8D3")

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
        st.dataframe(tabela_df, width="stretch")
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
