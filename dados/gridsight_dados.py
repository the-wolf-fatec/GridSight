#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gridsight_dados.py - GridSight: baixa TUDO de uma vez.

  1. Distribuidoras: descobre no portal da ANEEL e baixa a BDGD das 30 principais.
  2. Ativos e candidatos: gera o SQL (tabelas asset e candidate_site) com os mesmos
     criterios que ja estao no seu banco.
  3. Relevo: baixa os ladrilhos SRTM (.hgt, ~90 m) das regioes dos dados -> backend/terrain
  4. Arvores e predios: baixa do OpenStreetMap, no MESMO formato do cache do backend
     (ladrilho de 0,05 graus, celula de 0,0002 graus) -> backend/clutter

Instalar uma vez:      py -m pip install geopandas pyogrio requests
Rodar (na pasta dados): py gridsight_dados.py                  # faz tudo, 30 principais
Ver o que existe:       py gridsight_dados.py --listar
So uma etapa:           py gridsight_dados.py --so bdgd | relevo | arvores
Teste rapido:           py gridsight_dados.py --max 2

Pode ser interrompido e rodado de novo: o que ja foi baixado/processado e pulado.
Cada BDGD tem varios GB; o .zip e apagado logo depois de usado (--manter guarda).
Reserve ~10 GB livres. Veja todas as opcoes com:  py gridsight_dados.py --help

ATENCAO: o ambiente onde este script foi escrito nao alcanca ANEEL, Overpass nem AWS.
O leitor da BDGD, o SQL e o formato dos ladrilhos de arvores/predios foram testados
com dados sinteticos; os downloads reais acontecem na sua primeira execucao.
"""
import argparse
import glob
import gzip
import json
import math
import os
import re
import shutil
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ======================================================================================
# PARAMETROS (os mesmos que o backend e o seu banco ja usam)
# ======================================================================================
AQUI = Path(__file__).resolve().parent

# ---- ativos e candidatos (iguais ao gerar_sql.py / baixar_bdgd_30.py) ----
MAX_UCMT = 1000          # ativos de media tensao por distribuidora (amostra espalhada)
MAX_UNTRMT = 1500        # transformadores em poste por distribuidora (amostra espalhada)
# UCAT (alta tensao), SUB (subestacoes) e UNCRMT (chaves/religadores) entram completos.
SITUACAO_ATIVA = "AT"    # so entram itens com SIT_ATIV == 'AT'
BRASIL = (-34.0, 6.0, -74.0, -34.0)   # lat_min, lat_max, lon_min, lon_max (descarta erros de projecao)
BANCO = "tecsys_gateway"

# ---- relevo ----
SKADI = "https://elevation-tiles-prod.s3.amazonaws.com/skadi/"   # SRTM publico na AWS
MARGEM_RELEVO_KM = 10.0  # margem ao redor dos pontos para escolher os ladrilhos de 1 grau

# ---- arvores e predios (iguais a ClutterTile / OverpassClutterParser / ClutterService) ----
TILE_DEG = 0.05
CELL_DEG = 0.0002
N = int(round(TILE_DEG / CELL_DEG))   # 250
CACHE_VERSION = "v2"                  # t_<i>_<j>_v2.bin
ARVORE_M = 15                         # mata/floresta
PREDIO_PADRAO_M = 8                   # predio sem altura nem andares
ANDAR_M = 3.2                         # building:levels x 3,2 m
OVERPASS = "https://overpass-api.de/api/interpreter"
OVERPASS_ALTERNATIVO = "https://overpass.kumi.systems/api/interpreter"
PAUSA_OVERPASS_S = 1.5                # educacao com o servidor publico (igual ao backend)
RAIO_ARVORES_KM = 5.0                 # faixa ao redor dos candidatos
MAX_LADRILHOS = 400                   # por distribuidora (0 = sem limite)

# ---- portal da ANEEL ----
API = "https://dadosabertos-aneel.opendata.arcgis.com/api/search/v1/collections/all/items"
DOWNLOAD = "https://www.arcgis.com/sharing/rest/content/items/{id}/data"
TITULO = re.compile(r"^(?P<nome>.+?)_(?P<cod>\d+)_(?P<data>\d{4}-\d{2}-\d{2})_(?P<versao>[A-Z]?\d+)")
LOTE = 200_000   # feicoes lidas por vez (controla memoria)

# As 30 principais (ordem = prioridade).
PRINCIPAIS = [
    "Enel SP", "CPFL Paulista", "CPFL Piratininga", "EDP SP", "Elektro", "Cemig", "Light", "Copel", "Celesc",
    "Enel RJ", "Enel CE", "Energisa Sul Sudeste", "EDP ES", "RGE Sul", "CPFL Santa Cruz", "Equatorial Para",
    "Equatorial Maranhao", "Equatorial Piaui", "Equatorial Alagoas", "Equatorial Goias", "Energisa Mato Grosso",
    "Energisa Mato Grosso do Sul", "Energisa Minas Rio", "Energisa Sergipe", "Energisa Paraiba", "Energisa Tocantins",
    "Coelba", "Cosern", "Neoenergia Pernambuco", "Neoenergia Brasilia",
]
# Grafias alternativas no portal (cada alternativa = palavras que tem de aparecer juntas).
ALIAS = {
    "Energisa Sul Sudeste": ["energisa sul sudeste", "energisa ss"],
    "Elektro": ["elektro"],
    "Equatorial Para": ["equatorial para", "equatorial pa", "celpa"],
    "Equatorial Maranhao": ["equatorial maranhao", "equatorial ma", "cemar"],
    "Equatorial Piaui": ["equatorial piaui", "equatorial pi", "cepisa"],
    "Equatorial Alagoas": ["equatorial alagoas", "equatorial al", "ceal"],
    "Equatorial Goias": ["equatorial goias", "equatorial go", "celg"],
    "Energisa Mato Grosso": ["energisa mato grosso", "energisa mt", "cemat"],
    "Energisa Mato Grosso do Sul": ["energisa mato grosso do sul", "energisa ms", "enersul"],
    "Energisa Sergipe": ["energisa sergipe", "energisa se", "energipe"],
    "Energisa Paraiba": ["energisa paraiba", "energisa pb", "epb"],
    "Energisa Tocantins": ["energisa tocantins", "energisa to", "etm"],
    "Light": ["light"],
    "Copel": ["copel"],
    "Celesc": ["celesc"],
}
EXCLUI = {"Energisa Mato Grosso": ["sul", "ms"]}   # evita confundir MT com MS
# As 5 originais mantem o codigo ANEEL e o nome usado no app/banco (nao duplicam na lista).
CODIGO_FIXO = {"390": "Enel São Paulo", "391": "EDP São Paulo", "63": "CPFL Paulista",
               "2937": "CPFL Piratininga", "385": "Neoenergia Elektro"}


# ======================================================================================
# Utilidades
# ======================================================================================
def norm(s):
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9 ]+", " ", s)


def slug(s):
    return re.sub(r"[^A-Za-z0-9]+", "_", unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()).strip("_")


def q(s):
    return "'" + str(s).replace("\\", "\\\\").replace("'", "''") + "'"


def dentro_do_brasil(lat, lon):
    return BRASIL[0] <= lat <= BRASIL[1] and BRASIL[2] <= lon <= BRASIL[3]


def espacado(lista, n):
    """n itens espalhados de forma uniforme (mesma regra do gerar_sql.py)."""
    if not n or len(lista) <= n:
        return list(lista)
    passo = len(lista) / n
    return [lista[int(i * passo)] for i in range(n)]


def importar_requests():
    try:
        import requests
        return requests
    except ImportError:
        sys.exit("Falta instalar:  py -m pip install geopandas pyogrio requests")


def importar_geo():
    try:
        import geopandas as gpd
        import pyogrio
        return gpd, pyogrio
    except ImportError:
        sys.exit("Falta instalar:  py -m pip install geopandas pyogrio requests")


# ======================================================================================
# ETAPA 1 - distribuidoras (portal da ANEEL)
# ======================================================================================
def _uma_passada(requests, tag):
    itens, url, params, total = {}, API, {"tags": tag, "limit": 100}, None
    while url:
        r = requests.get(url, params=params, timeout=60)
        r.raise_for_status()
        js = r.json()
        total = js.get("numberMatched", total)
        for f in js.get("features", []):
            itens[f["id"]] = f
        url = next((l["href"] for l in js.get("links", []) if l.get("rel") == "next"), None)
        params = None
    return itens, total


def listar_portal(tag="distribuicao", max_passadas=8):
    """A paginacao da API nao tem ordem estavel: lista varias vezes e junta (como no bdgd_aneel.py)."""
    requests = importar_requests()
    todos, total, sem_novidade = {}, None, 0
    for i in range(1, max_passadas + 1):
        novos, total = _uma_passada(requests, tag)
        antes = len(todos)
        todos.update(novos)
        print(f"  passada {i}: {len(todos)} itens unicos de {total} no portal", flush=True)
        sem_novidade = sem_novidade + 1 if len(todos) == antes else 0
        if total and len(todos) >= total and i >= 2:
            break
        if sem_novidade >= 2:
            break
    linhas = []
    for f in todos.values():
        p = f["properties"]
        if p.get("type") != "File Geodatabase":
            continue
        m = TITULO.match(p.get("title", ""))
        if not m:
            continue
        linhas.append({"nome": m["nome"], "cod": m["cod"], "data": m["data"], "versao": m["versao"],
                       "mb": round((p.get("size") or 0) / 1e6, 1), "titulo": p["title"], "id": p["id"],
                       "url": DOWNLOAD.format(id=p["id"])})
    return linhas


def casa(texto, alternativas):
    palavras = set(norm(texto).split())
    t = " " + norm(texto) + " "
    for alt in alternativas:
        if all((tk in palavras) if len(tk) <= 3 else (tk in t) for tk in alt.split()):
            return True
    return False


def mais_recente(itens):
    """Fica so a edicao mais recente de cada distribuidora (data-base, depois versao/titulo)."""
    por = {}
    for it in itens:
        por.setdefault(it["cod"], []).append(it)
    return [max(v, key=lambda x: (x["data"], x["versao"], x["titulo"])) for v in por.values()]


def selecionar(itens, a):
    itens = [i for i in itens if not a.data_base or i["data"] == a.data_base]
    itens = mais_recente(itens)
    if a.distribuidoras:
        termos = [norm(t).split() for t in a.distribuidoras]
        sel = [i for i in itens if any(all(w in norm(i["nome"] + " " + i["cod"]).split() or w in norm(i["nome"])
                                           for w in t) for t in termos)]
        return [(i["nome"], i) for i in sel], []
    if a.todas:
        return [(i["nome"], i) for i in sorted(itens, key=lambda x: -x["mb"])], []
    if a.top:
        return [(i["nome"], i) for i in sorted(itens, key=lambda x: -x["mb"])[: a.top]], []
    achados, faltam = [], []
    usados = set()
    for alvo in PRINCIPAIS:
        alt = ALIAS.get(alvo, [norm(alvo)])
        cand = [i for i in itens if i["cod"] not in usados and casa(i["nome"], alt)
                and not any(w in norm(i["nome"]).split() for w in EXCLUI.get(alvo, []))]
        if cand:
            best = max(cand, key=lambda x: (x["data"], x["versao"]))
            usados.add(best["cod"])
            achados.append((alvo, best))
        else:
            faltam.append(alvo)
    for i in itens:   # as 5 originais sempre entram (codigo fixo), mesmo se o nome nao casou
        if i["cod"] in CODIGO_FIXO and i["cod"] not in usados:
            usados.add(i["cod"])
            achados.append((CODIGO_FIXO[i["cod"]], i))
    return achados, faltam


def nome_exibicao(nome_portal, cod):
    if cod in CODIGO_FIXO:
        return CODIGO_FIXO[cod]
    return nome_portal.replace("_", " ").replace("-", " ").strip().title()


def baixar_zip(url, destino, tentativas=8):
    """Download com retomada (arquivo .part): se a rede cair, continua de onde parou."""
    requests = importar_requests()
    destino = Path(destino)
    destino.parent.mkdir(parents=True, exist_ok=True)
    if destino.exists() and zipfile.is_zipfile(destino):
        return destino
    tmp = destino.with_suffix(".part")
    ultimo = None
    for n in range(1, tentativas + 1):
        feito = tmp.stat().st_size if tmp.exists() else 0
        try:
            cab = {"Range": f"bytes={feito}-"} if feito else {}
            with requests.get(url, stream=True, headers=cab, timeout=(30, 60)) as r:
                if r.status_code == 416:
                    break
                r.raise_for_status()
                if feito and r.status_code != 206:
                    feito = 0
                total = int(r.headers.get("Content-Length", 0)) + feito
                with open(tmp, "ab" if feito else "wb") as f:
                    for bloco in r.iter_content(1 << 20):
                        f.write(bloco)
                        feito += len(bloco)
                        if total:
                            print(f"\r    baixando {feito / 1e6:,.0f}/{total / 1e6:,.0f} MB", end="", flush=True)
            print()
            break
        except Exception as e:
            ultimo = e
            print(f"\n    download interrompido ({e.__class__.__name__}), tentativa {n}/{tentativas}; continuo de onde parou...",
                  flush=True)
            time.sleep(5 * n)
    else:
        raise RuntimeError(f"download falhou depois de {tentativas} tentativas: {ultimo}")
    if not zipfile.is_zipfile(tmp):
        tmp.unlink(missing_ok=True)
        raise RuntimeError("arquivo baixado nao e um .zip valido")
    os.replace(tmp, destino)
    return destino


def abrir_gdb(arquivo, pasta_tmp):
    """Aceita .zip (extrai o .gdb) ou a propria pasta .gdb. Devolve o caminho do .gdb extraido."""
    arquivo = str(arquivo)
    if os.path.isdir(arquivo) and arquivo.lower().endswith(".gdb"):
        return arquivo
    alvo = os.path.join(pasta_tmp, slug(os.path.splitext(os.path.basename(arquivo))[0])[:40])
    if not os.path.isdir(alvo):
        with zipfile.ZipFile(arquivo) as z:
            z.extractall(alvo)
    for raiz, dirs, _ in os.walk(alvo):
        for d in dirs:
            if d.lower().endswith(".gdb"):
                return os.path.join(raiz, d)
    return None


def caminhos_gdb(arq, gdb):
    """Formas de abrir o mesmo .gdb: pasta extraida e, se der, direto de dentro do .zip."""
    out = []
    if gdb:
        out.append(os.path.abspath(gdb).replace("\\", "/"))
    if str(arq).lower().endswith(".zip"):
        try:
            with zipfile.ZipFile(arq) as z:
                ger = [n[: n.index(".gdb/") + 4] for n in z.namelist() if ".gdb/" in n]
            if ger:
                out.append("/vsizip/" + os.path.abspath(arq).replace("\\", "/") + "/" + ger[0])
        except Exception:
            pass
    return out


# ======================================================================================
# ETAPA 2 - ativos e candidatos (le a BDGD e gera linhas para o SQL)
# ======================================================================================
def achar_camada(layers, base):
    """'UCMT_tab' -> 'UCMT' (o sufixo muda entre versoes da BDGD). Nome exato primeiro."""
    nomes = {re.sub(r"_tab$", "", l, flags=re.I).upper(): l for l in layers}
    if base in nomes:
        return nomes[base]
    for k, l in nomes.items():
        if k.startswith(base) and not k[len(base):len(base) + 1].isalpha():
            return l
    return None


def ponto_de(geom):
    """(lat, lon) de qualquer geometria: ponto como esta; poligono = centroide da maior parte."""
    try:
        if geom is None or geom.is_empty:
            return None
        if geom.geom_type == "Point":
            return geom.y, geom.x
        partes = list(getattr(geom, "geoms", [geom]))
        if partes and partes[0].geom_type == "Polygon":
            geom = max(partes, key=lambda p: p.area)
        c = geom.centroid
        return c.y, c.x
    except Exception:
        return None


def ler_camada(gpd, pyogrio, caminho, camada, limite, so_ativos):
    """Le uma camada em lotes e devolve um DataFrame (EPSG:4326) com no maximo ~4x o limite de linhas,
    espalhadas por toda a camada (memoria controlada mesmo em distribuidoras com milhoes de linhas)."""
    import warnings
    info = pyogrio.read_info(caminho, layer=camada)
    campos = list(info["fields"])
    desejadas = ["SIT_ATIV", "COD_ID", "COD_ID_ENCR", "NOME", "BRR", "CEP", "CLAS_SUB", "TIP_UNID", "PN_CON"]
    cols = [c for c in desejadas if c in campos]
    where = f"SIT_ATIV = '{SITUACAO_ATIVA}'" if so_ativos and "SIT_ATIV" in campos else None
    total = max(0, info.get("features") or 0)   # -1 = o driver nao sabe contar
    passo = max(1, total // (limite * 4)) if limite and total > limite * 4 else 1
    partes, pulados = [], 0
    while True:
        kw = dict(layer=camada, columns=cols, skip_features=pulados, max_features=LOTE)
        if where:
            kw["where"] = where
        g = pyogrio.read_dataframe(caminho, **kw)
        if len(g) == 0:
            break
        ini = (-pulados) % passo
        pulados += len(g)
        g = g.iloc[ini::passo]
        if hasattr(g, "geometry") and getattr(g, "crs", None) is not None:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                g = g.to_crs(4326)
        partes.append(g)
        if pulados >= total and total:
            break
    if not partes:
        return None
    import pandas as pd
    return pd.concat(partes, ignore_index=True) if len(partes) > 1 else partes[0]


def pontos_via_ponnot(gpd, pyogrio, caminho, layers, df):
    """Se a camada nao tem geometria, acha o ponto pela coluna PN_CON -> PONNOT.COD_ID."""
    ponnot = achar_camada(layers, "PONNOT")
    if not ponnot or "PN_CON" not in df.columns:
        return {}
    precisa = set(df["PN_CON"].dropna().astype(str))
    achou, pulados = {}, 0
    while len(achou) < len(precisa):
        g = pyogrio.read_dataframe(caminho, layer=ponnot, columns=["COD_ID"], skip_features=pulados, max_features=LOTE)
        if len(g) == 0:
            break
        pulados += len(g)
        if getattr(g, "crs", None) is not None:
            g = g.to_crs(4326)
        for cod, geom in zip(g["COD_ID"].astype(str), g.geometry):
            if cod in precisa and cod not in achou:
                p = ponto_de(geom)
                if p:
                    achou[cod] = p
    return achou


def ler_gdb(caminho, cod_agente, nome_dist, max_ucmt=MAX_UCMT, max_untrmt=MAX_UNTRMT):
    """Devolve (ativos, candidatos): listas de (id, nome, tipo, lat, lon, distribuidora)."""
    gpd, pyogrio = importar_geo()
    layers = [l[0] for l in pyogrio.list_layers(caminho)]
    ativos, cands = [], []
    vistos_a, vistos_c = set(), set()

    def processar(base, limite, tag, destino, vistos, rotulo, tipo_padrao, so_ativos, uc):
        camada = achar_camada(layers, base)
        if not camada:
            print(f"    (camada {base} nao existe nesta base)", flush=True)
            return
        df = ler_camada(gpd, pyogrio, caminho, camada, limite, so_ativos)
        if df is None or len(df) == 0:
            return
        sem_geom = getattr(df, "_geometry_column_name", None) is None or bool(df.geometry.isna().all())
        via_pn = pontos_via_ponnot(gpd, pyogrio, caminho, layers, df) if sem_geom else {}
        linhas = []
        for i in range(len(df)):
            r = df.iloc[i]
            pt = via_pn.get(str(r.get("PN_CON"))) if sem_geom else ponto_de(df.geometry.iloc[i])
            if not pt or not dentro_do_brasil(*pt):
                continue
            linhas.append((r, pt))
        for r, (lat, lon) in espacado(linhas, limite):
            def v(c):
                x = r.get(c)
                return "" if x is None or str(x) == "nan" else str(x).strip()
            if uc:   # ativos: id pelo COD_ID_ENCR, nome pelo bairro/CEP, tipo pela classe
                cod = (v("COD_ID_ENCR") or v("COD_ID"))[:16] or str(len(destino))
                brr, cep = v("BRR"), v("CEP")
                nome = brr or ("UC " + cep if cep else "Unidade Consumidora")
                tipo = v("CLAS_SUB") or tipo_padrao
                chave = (round(lat, 6), round(lon, 6))
            else:    # candidatos
                cod = v("COD_ID") or str(len(destino))
                nm = v("NOME")
                nome = (rotulo + " " + nm) if (base == "SUB" and nm) else (f"{rotulo} {cod}" if base != "SUB" else "Subestação")
                tipo = tipo_padrao
                chave = (tag, cod)
            if chave in vistos:
                continue
            vistos.add(chave)
            destino.append((f"bdgd-{tag}-{cod_agente}-{cod}", nome, tipo, lat, lon, nome_dist))
        print(f"    {base}: {sum(1 for d in destino if d[0].startswith('bdgd-' + tag + '-'))} itens", flush=True)

    processar("UCAT", None, "ucat", ativos, vistos_a, "UC", "UC", True, True)
    processar("UCMT", max_ucmt, "ucmt", ativos, vistos_a, "UC", "UC", True, True)
    processar("SUB", None, "sub", cands, vistos_c, "SE", "Subestação", False, False)
    processar("UNCRMT", None, "uncrmt", cands, vistos_c, "Chave/Religador", "Chave/Religador", True, False)
    processar("UNTRMT", max_untrmt, "untrmt", cands, vistos_c, "Transformador", "Transformador", True, False)
    return ativos, cands


def escrever_sql(arquivo, ativos, cands, nomes):
    def ins(tabela, rows, lote=500):
        out = []
        for i in range(0, len(rows), lote):
            v = ",\n  ".join(f"({q(r[0])}, {q(r[1])}, {q(r[2])}, {r[3]:.8f}, {r[4]:.8f}, {q(r[5])})" for r in rows[i:i + lote])
            out.append(f"INSERT INTO {tabela} (id, name, type, latitude, longitude, distribuidora) VALUES\n  {v};\n")
        return "".join(out)
    with open(arquivo, "w", encoding="utf-8") as f:
        f.write(f"-- GridSight - BDGD/ANEEL de {len(nomes)} distribuidoras: {', '.join(nomes)}\n")
        f.write(f"-- Ativos     : UCAT completo + amostra espalhada de UCMT ({MAX_UCMT} por distribuidora), so SIT_ATIV = 'AT'\n")
        f.write(f"-- Candidatos : subestacoes (centroide), chaves/religadores (UNCRMT) e amostra de transformadores (UNTRMT, {MAX_UNTRMT})\n")
        f.write("-- Pode ser rodado varias vezes: apaga so o que comeca com 'bdgd-' (itens 'manual-...' ficam).\n")
        f.write("-- Gerado por gridsight_dados.py\n\n")
        f.write(f"USE {BANCO};\nSET NAMES utf8mb4;\nSET SQL_SAFE_UPDATES = 0;\n\n")
        f.write("DELETE FROM scenario_gateway WHERE candidate_site_id LIKE 'bdgd-%';\n")
        f.write("DELETE FROM candidate_site WHERE id LIKE 'bdgd-%';\nDELETE FROM asset WHERE id LIKE 'bdgd-%';\n\n")
        f.write("-- ===== ATIVOS =====\n" + ins("asset", ativos))
        f.write("\n-- ===== LOCAIS CANDIDATOS =====\n" + ins("candidate_site", cands))
        f.write("\nSET SQL_SAFE_UPDATES = 1;\n\nSELECT distribuidora, COUNT(*) AS ativos FROM asset GROUP BY distribuidora;\n"
                "SELECT distribuidora, type, COUNT(*) AS candidatos FROM candidate_site GROUP BY distribuidora, type;\n")


def etapa_bdgd(a, pastas):
    fontes = []   # (nome_exibicao, cod_agente, url_ou_arquivo)
    if a.pasta:
        for p in sorted(glob.glob(os.path.join(a.pasta, "*.zip")) + glob.glob(os.path.join(a.pasta, "*.gdb"))):
            base = os.path.splitext(os.path.basename(p))[0]
            m = TITULO.match(base)
            cod = m["cod"] if m else slug(base)[:8]
            fontes.append((nome_exibicao(m["nome"] if m else base, cod), cod, p))
    elif a.urls:
        for i, l in enumerate(open(a.urls, encoding="utf-8")):
            l = l.strip()
            if l:
                base = os.path.splitext(os.path.basename(l.split("?")[0]))[0] or f"dist{i}"
                fontes.append((base, str(i), l))
    else:
        print("Consultando o portal da ANEEL...", flush=True)
        itens = listar_portal()
        if not itens:
            sys.exit("O portal nao devolveu nada. Baixe os .zip a mao no site da ANEEL e use --pasta, ou passe links com --urls.")
        pasta_inv = pastas["saida"]
        pasta_inv.mkdir(parents=True, exist_ok=True)
        with open(pasta_inv / "inventario_distribuidoras.csv", "w", encoding="utf-8") as f:
            f.write("nome;cod_agente;data_base;versao;mb;titulo\n")
            for i in sorted(itens, key=lambda x: (x["nome"], x["data"])):
                f.write(f"{i['nome']};{i['cod']};{i['data']};{i['versao']};{i['mb']};{i['titulo']}\n")
        achados, faltam = selecionar(itens, a)
        print(f"\nSelecionadas {len(achados)} distribuidora(s):")
        for nome, it in achados:
            print(f"   OK   {nome:32s} cod {it['cod']:>5s}  base {it['data']}  {it['mb']:>8,.0f} MB")
        for nome in faltam:
            print(f"   falta {nome}  (use --distribuidoras ou veja inventario_distribuidoras.csv)")
        if a.listar:
            print(f"\nInventario completo em {pasta_inv / 'inventario_distribuidoras.csv'}")
            return None
        fontes = [(nome_exibicao(it["nome"], it["cod"]), it["cod"], it["url"]) for _, it in achados]
        if not fontes:
            sys.exit("Nada selecionado.")
    fontes = fontes[: a.max]

    cache = pastas["cache"]
    cache.mkdir(parents=True, exist_ok=True)
    tmp = cache / "gdb"
    todos_a, todos_c, nomes = [], [], []
    for nome, cod, src in fontes:
        ck = cache / f"ok_{slug(cod)}_{slug(nome)}.json"
        if ck.exists():
            d = json.load(open(ck, encoding="utf-8"))
            todos_a += [tuple(r) for r in d["ativos"]]
            todos_c += [tuple(r) for r in d["cands"]]
            nomes.append(d["nome"])
            print(f"[{d['nome']}] ja processada antes (ativos={len(d['ativos'])} candidatos={len(d['cands'])}), pulei", flush=True)
            continue
        falhou, arq = False, src
        try:
            print(f"[{nome}] (cod {cod})", flush=True)
            if str(src).startswith("http"):
                arq = baixar_zip(src, cache / f"{slug(nome)}_{slug(cod)}.zip")
            gdb = abrir_gdb(arq, str(tmp))
            at = cd = None
            erros = []
            for caminho in caminhos_gdb(arq, gdb):
                try:
                    at, cd = ler_gdb(caminho, cod, nome, a.max_ucmt, a.max_untrmt)
                    break
                except Exception as e:
                    erros.append(f"{caminho[:50]}...: {e}")
            if at is None:
                raise RuntimeError("nao consegui abrir o .gdb. " + " | ".join(erros))
            print(f"[{nome}] ativos={len(at)} candidatos={len(cd)}", flush=True)
            if at or cd:
                todos_a += at
                todos_c += cd
                nomes.append(nome)
                json.dump({"nome": nome, "ativos": at, "cands": cd}, open(ck, "w", encoding="utf-8"))
        except Exception as e:   # uma distribuidora com problema nao derruba as outras
            falhou = True
            print(f"[{nome}] FALHOU: {e}", flush=True)
        finally:
            if isinstance(arq, (str, Path)) and str(arq):
                pasta_ext = tmp / slug(os.path.splitext(os.path.basename(str(arq)))[0])[:40]
                shutil.rmtree(pasta_ext, ignore_errors=True)
                if str(src).startswith("http") and not a.manter and not falhou and os.path.exists(str(arq)):
                    os.remove(str(arq))
    if not nomes:
        sys.exit("Nenhuma distribuidora processada.")
    escrever_sql(a.saida_sql, todos_a, todos_c, nomes)
    print(f"\nSQL gerado: {os.path.abspath(a.saida_sql)}  ({len(todos_a)} ativos, {len(todos_c)} candidatos, {len(nomes)} distribuidoras)")
    return todos_a, todos_c


def carregar_checkpoints(cache):
    """Pontos ja processados (para rodar so relevo/arvores depois)."""
    ativos, cands = [], []
    for f in sorted(glob.glob(str(cache / "ok_*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        ativos += [tuple(r) for r in d["ativos"]]
        cands += [tuple(r) for r in d["cands"]]
    return ativos, cands


# ======================================================================================
# ETAPA 3 - relevo (SRTM .hgt, cópia pública na AWS)
# ======================================================================================
def nome_hgt(lat, lon):
    return f"{'S' if lat < 0 else 'N'}{abs(lat):02d}{'W' if lon < 0 else 'E'}{abs(lon):03d}"


def ladrilhos_relevo(pontos, margem_km=MARGEM_RELEVO_KM):
    """Nomes dos ladrilhos SRTM de 1 grau que cobrem os pontos (+ margem)."""
    dlat = margem_km / 111.0
    achados = set()
    vistos = set()
    for lat, lon in pontos:
        cel = (round(lat, 2), round(lon, 2))          # evita repetir milhares de pontos iguais
        if cel in vistos:
            continue
        vistos.add(cel)
        dlon = margem_km / (111.0 * max(0.2, math.cos(math.radians(lat))))
        for la in (lat - dlat, lat + dlat):
            for lo in (lon - dlon, lon + dlon):
                achados.add(nome_hgt(math.floor(la), math.floor(lo)))
    return sorted(achados)


def ladrilhos_bbox(lat_min, lon_min, lat_max, lon_max):
    out = []
    for la in range(math.floor(min(lat_min, lat_max)), math.floor(max(lat_min, lat_max)) + 1):
        for lo in range(math.floor(min(lon_min, lon_max)), math.floor(max(lon_min, lon_max)) + 1):
            out.append(nome_hgt(la, lo))
    return out


def hgt_leve(dados: bytes) -> bytes:
    """3601x3601 (~30 m) -> 1201x1201 (~90 m), 1 amostra a cada 3. Mantem o formato .hgt (int16 big-endian)."""
    import array
    n = 3601
    if len(dados) != n * n * 2:
        return dados
    arr = array.array("H")
    arr.frombytes(dados)
    out = array.array("H")
    for r in range(0, n, 3):
        out.extend(arr[r * n: (r + 1) * n: 3])
    return out.tobytes()


def baixar_hgt(nm, destino, completo, base=SKADI):
    arq = os.path.join(destino, nm + ".hgt")
    if os.path.exists(arq) and os.path.getsize(arq) > 1_000_000:
        return "ja existe"
    url = f"{base}{nm[:3]}/{nm}.hgt.gz"
    err = ""
    for tentativa in range(1, 4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "GridSight/1.0"}), timeout=90) as r:
                dados = gzip.decompress(r.read())
            dados = dados if completo else hgt_leve(dados)
            tmp = arq + ".part"
            with open(tmp, "wb") as f:
                f.write(dados)
            os.replace(tmp, arq)
            return f"ok ({len(dados) / 1e6:.1f} MB)"
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                return f"sem dado ({e.code}) - provavelmente oceano/fora da cobertura"
            err = f"HTTP {e.code}"
        except Exception as e:
            err = str(e)
        time.sleep(2 * tentativa)
    return f"FALHOU: {err}"


def etapa_relevo(nomes, destino, completo):
    os.makedirs(destino, exist_ok=True)
    print(f"\nRelevo: {len(nomes)} ladrilho(s) -> {os.path.abspath(destino)}  ({'original ~30 m' if completo else 'leve ~90 m'})", flush=True)
    falhas = 0
    for i, nm in enumerate(nomes, 1):
        res = baixar_hgt(nm, destino, completo)
        falhas += res.startswith("FALHOU")
        print(f"[{i}/{len(nomes)}] {nm}: {res}", flush=True)
    print("Relevo concluido." if not falhas else f"Relevo com {falhas} falha(s): rode de novo, so os que faltam serao baixados.")


# ======================================================================================
# ETAPA 4 - arvores e predios (OpenStreetMap -> cache do backend)
# ======================================================================================
class Ladrilho:
    """Mesma grade do ClutterTile.java: 250x250 bytes; bits 0..6 = altura (m), bit 7 = arvore."""

    def __init__(self, i, j, dados=None):
        self.i, self.j = i, j
        self.h = bytearray(dados) if dados is not None else bytearray(N * N)

    @property
    def lat0(self):
        return self.i * TILE_DEG

    @property
    def lon0(self):
        return self.j * TILE_DEG

    def _raise(self, r, c, altura, arvore):
        if r < 0 or c < 0 or r >= N or c >= N:
            return
        k = r * N + c
        altura = min(127, altura)
        if (self.h[k] & 0x7F) < altura:
            self.h[k] = altura | (0x80 if arvore else 0)

    def preencher_caixa(self, min_lat, min_lon, max_lat, max_lon, altura, arvore):
        r0 = math.floor((min_lat - self.lat0) / CELL_DEG)
        r1 = math.floor((max_lat - self.lat0) / CELL_DEG)
        c0 = math.floor((min_lon - self.lon0) / CELL_DEG)
        c1 = math.floor((max_lon - self.lon0) / CELL_DEG)
        for r in range(max(0, r0), min(N - 1, r1) + 1):
            for c in range(max(0, c0), min(N - 1, c1) + 1):
                self._raise(r, c, altura, arvore)

    def preencher_poligono(self, lats, lons, altura, arvore):
        n = len(lats)
        if n < 3:
            return
        r0 = max(0, math.floor((min(lats) - self.lat0) / CELL_DEG))
        r1 = min(N - 1, math.floor((max(lats) - self.lat0) / CELL_DEG))
        for r in range(r0, r1 + 1):
            y = self.lat0 + (r + 0.5) * CELL_DEG
            xs = []
            b = n - 1
            for a in range(n):
                ya, yb = lats[a], lats[b]
                if (ya > y) != (yb > y):
                    xs.append(lons[a] + (y - ya) / (yb - ya) * (lons[b] - lons[a]))
                b = a
            xs.sort()
            for m in range(0, len(xs) - 1, 2):
                c0 = math.ceil((xs[m] - self.lon0) / CELL_DEG - 0.5)
                c1 = math.floor((xs[m + 1] - self.lon0) / CELL_DEG - 0.5)
                for c in range(max(0, c0), min(N - 1, c1) + 1):
                    self._raise(r, c, altura, arvore)


def _numero(s):
    if s is None:
        return None
    try:
        return float(re.sub(r"[^0-9.,-]", "", str(s)).replace(",", "."))
    except ValueError:
        return None


def _arredonda(x):           # Math.round do Java (meio para cima)
    return math.floor(x + 0.5)


def _limita(h):
    return int(max(3, min(127, _arredonda(h))))


def altura_para(tags):
    """OverpassClutterParser.heightFor"""
    if not tags:
        return 0
    b = tags.get("building")
    if b is not None and b != "no":
        h = _numero(tags.get("height"))
        if h is not None:
            return _limita(h)
        lv = _numero(tags.get("building:levels"))
        if lv is not None:
            return _limita(lv * ANDAR_M)
        return PREDIO_PADRAO_M
    if tags.get("natural") == "wood" or tags.get("landuse") == "forest":
        return ARVORE_M
    return 0


def e_arvore(tags):
    """OverpassClutterParser.isTree"""
    return bool(tags) and (tags.get("natural") == "wood" or tags.get("landuse") == "forest") and tags.get("building") is None


def _geometria(t, geom, altura, arvore):
    if len(geom) < 3:
        return
    t.preencher_poligono([g.get("lat", 0.0) for g in geom], [g.get("lon", 0.0) for g in geom], altura, arvore)


def _caixa(t, b, altura, arvore):
    t.preencher_caixa(b.get("minlat", 0.0), b.get("minlon", 0.0), b.get("maxlat", 0.0), b.get("maxlon", 0.0), altura, arvore)


def interpretar_overpass(resposta, t):
    """OverpassClutterParser.parse: preenche o ladrilho com a resposta JSON do Overpass."""
    elementos = resposta.get("elements")
    if not isinstance(elementos, list):
        return
    for el in elementos:
        tags = el.get("tags") or {}
        altura = altura_para(tags)
        if altura <= 0:
            continue
        arvore = e_arvore(tags)
        tipo = el.get("type", "")
        if tipo == "way":
            if "geometry" in el:
                _geometria(t, el["geometry"], altura, arvore)
            elif isinstance(el.get("bounds"), dict):
                _caixa(t, el["bounds"], altura, arvore)
        elif tipo == "relation":
            for m in el.get("members") or []:
                if m.get("role") == "outer" and "geometry" in m:
                    _geometria(t, m["geometry"], altura, arvore)
            if not isinstance(el.get("members"), list) and isinstance(el.get("bounds"), dict):
                _caixa(t, el["bounds"], altura, arvore)


def indice_ladrilho(grau):
    return math.floor(grau / TILE_DEG + 1e-9)


def arquivo_ladrilho(pasta, i, j):
    return Path(pasta) / f"t_{i}_{j}_{CACHE_VERSION}.bin"


_ultimo_overpass = [0.0]


def consulta_overpass(requests, urls, ql):
    ultimo = None
    for tentativa in range(1, 5):
        for url in urls:
            espera = PAUSA_OVERPASS_S - (time.time() - _ultimo_overpass[0])
            if espera > 0:
                time.sleep(espera)
            try:
                r = requests.post(url, data={"data": ql}, timeout=150,
                                  headers={"User-Agent": "GridSight-Tecsys-FatecSJC/1.0 (academic project)"})
                _ultimo_overpass[0] = time.time()
                if r.status_code == 200:
                    return r.json()
                ultimo = f"HTTP {r.status_code}"
            except Exception as e:
                _ultimo_overpass[0] = time.time()
                ultimo = e.__class__.__name__
        time.sleep(10 * tentativa)   # 429/504: o servidor publico esta ocupado; espera e tenta de novo
    raise RuntimeError(f"Overpass falhou ({ultimo})")


def baixar_ladrilho(requests, urls, i, j):
    s, w = i * TILE_DEG, j * TILE_DEG
    n, e = s + TILE_DEG, w + TILE_DEG
    box = f"{s:.5f},{w:.5f},{n:.5f},{e:.5f}"
    t = Ladrilho(i, j)
    veg = (f'[out:json][timeout:90];(way["natural"="wood"]({box});way["landuse"="forest"]({box});'
           f'relation["natural"="wood"]({box});relation["landuse"="forest"]({box}););out geom;')
    interpretar_overpass(consulta_overpass(requests, urls, veg), t)
    bld = f'[out:json][timeout:120];way["building"]({box});out tags bb;'
    interpretar_overpass(consulta_overpass(requests, urls, bld), t)
    return t


def ladrilhos_arvores(candidatos, raio_km, max_ladrilhos):
    """Ladrilhos de 0,05 graus que tocam um circulo (quadrado) de `raio_km` em torno de cada candidato.
    Ordena por quantos candidatos tocam o ladrilho (subestacao vale mais) e corta em `max_ladrilhos`."""
    dlat = raio_km / 111.0
    pontaje = {}
    for lat, lon, peso in candidatos:
        dlon = raio_km / (111.0 * max(0.2, math.cos(math.radians(lat))))
        for i in range(indice_ladrilho(lat - dlat), indice_ladrilho(lat + dlat) + 1):
            for j in range(indice_ladrilho(lon - dlon), indice_ladrilho(lon + dlon) + 1):
                pontaje[(i, j)] = pontaje.get((i, j), 0) + peso
    ordem = sorted(pontaje, key=lambda k: (-pontaje[k], k))
    return ordem[:max_ladrilhos] if max_ladrilhos else ordem


def etapa_arvores(grupos, pasta, a):
    """grupos: {nome_distribuidora: [(lat, lon, peso), ...]} ou {'regiao': [...]} (bbox)."""
    requests = importar_requests()
    urls = [a.overpass] + ([OVERPASS_ALTERNATIVO] if a.overpass == OVERPASS else [])
    pasta = Path(pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    feitos, falhas, ja = 0, 0, 0
    print(f"\nArvores e predios -> {pasta.resolve()}", flush=True)
    for nome, pontos in grupos.items():
        lista = ladrilhos_arvores(pontos, a.raio_km, a.max_ladrilhos)
        faltam = [(i, j) for i, j in lista if not arquivo_ladrilho(pasta, i, j).exists()]
        print(f"[{nome}] {len(lista)} ladrilho(s) de ~5 km; {len(lista) - len(faltam)} ja existem, {len(faltam)} a baixar", flush=True)
        for k, (i, j) in enumerate(faltam, 1):
            try:
                t = baixar_ladrilho(requests, urls, i, j)
                alvo = arquivo_ladrilho(pasta, i, j)
                tmp = alvo.with_suffix(".part")
                tmp.write_bytes(bytes(t.h))
                os.replace(tmp, alvo)
                feitos += 1
                cheio = sum(1 for b in t.h if b & 0x7F)
                print(f"   [{k}/{len(faltam)}] ladrilho {i},{j}: ok ({cheio} celulas com obstaculo)", flush=True)
            except Exception as e:
                falhas += 1
                print(f"   [{k}/{len(faltam)}] ladrilho {i},{j}: FALHOU ({e})", flush=True)
        ja += len(lista) - len(faltam)
    print(f"Arvores e predios: {feitos} baixado(s), {ja} ja existia(m), {falhas} falha(s)."
          + (" Rode de novo para tentar os que falharam." if falhas else ""))


# ======================================================================================
# Programa principal
# ======================================================================================
def achar_backend(informado=None):
    """Acha a pasta do backend (a que tem o pom.xml): a informada em --backend, ou procura ao lado do script,
    na pasta acima, no diretorio atual e no pai dele. Assim funciona com `dados` na raiz do projeto ou dentro de `frontend`."""
    if informado:
        return Path(informado).resolve()
    for base in (AQUI, AQUI.parent, AQUI.parent.parent, Path.cwd(), Path.cwd().parent):
        for cand in (base / "backend", base.parent / "backend"):
            if (cand / "pom.xml").is_file():
                return cand.resolve()
    padrao = (AQUI.parent / "backend").resolve()
    print(f"AVISO: nao achei a pasta do backend (a que tem o pom.xml). Vou usar {padrao}. "
          "Se estiver errado, use --backend \"caminho\\da\\pasta\\backend\".", flush=True)
    return padrao


def main(argv=None):
    ap = argparse.ArgumentParser(description="GridSight: baixa distribuidoras, ativos, candidatos, relevo, arvores e predios.")
    g = ap.add_argument_group("quais distribuidoras (padrao: as 30 principais)")
    g.add_argument("--listar", action="store_true", help="so mostra o que o portal da ANEEL tem e o que seria baixado")
    g.add_argument("--distribuidoras", nargs="+", metavar="NOME", help="busca por nome ou codigo, ex.: cemig light 390")
    g.add_argument("--top", type=int, help="as N maiores do portal (por tamanho)")
    g.add_argument("--todas", action="store_true", help="TODAS as distribuidoras do portal (centenas de GB!)")
    g.add_argument("--max", type=int, default=30, help="maximo de distribuidoras processadas (padrao 30; use 2 para testar)")
    g.add_argument("--data-base", help="ex.: 2025-12-31 (padrao: a mais recente de cada uma)")
    g.add_argument("--pasta", help="pasta com .zip/.gdb que voce ja baixou a mao")
    g.add_argument("--urls", help="arquivo de texto com um link .zip por linha")
    g.add_argument("--manter", action="store_true", help="nao apaga os .zip depois de usar")
    e = ap.add_argument_group("etapas")
    e.add_argument("--so", nargs="+", choices=["bdgd", "relevo", "arvores"], help="roda so estas etapas")
    e.add_argument("--pular-relevo", action="store_true")
    e.add_argument("--pular-arvores", action="store_true")
    p = ap.add_argument_group("parametros")
    p.add_argument("--max-ucmt", type=int, default=MAX_UCMT, help=f"ativos de media tensao por distribuidora (padrao {MAX_UCMT})")
    p.add_argument("--max-untrmt", type=int, default=MAX_UNTRMT, help=f"transformadores por distribuidora (padrao {MAX_UNTRMT})")
    p.add_argument("--raio-km", type=float, default=RAIO_ARVORES_KM, help=f"faixa de arvores/predios ao redor dos candidatos (padrao {RAIO_ARVORES_KM:g} km)")
    p.add_argument("--max-ladrilhos", type=int, default=MAX_LADRILHOS, help=f"ladrilhos de arvores/predios por distribuidora (padrao {MAX_LADRILHOS}; 0 = sem limite)")
    p.add_argument("--margem-relevo-km", type=float, default=MARGEM_RELEVO_KM)
    p.add_argument("--completo", action="store_true", help="relevo na resolucao original (~30 m, ~25 MB por ladrilho)")
    p.add_argument("--bbox", nargs=4, type=float, metavar=("LAT_MIN", "LON_MIN", "LAT_MAX", "LON_MAX"),
                   help="relevo e arvores/predios so desta regiao (sem usar as distribuidoras)")
    p.add_argument("--overpass", default=OVERPASS)
    o = ap.add_argument_group("pastas")
    o.add_argument("--backend", default=None, help="pasta do backend (terrain/ e clutter/ ficam dentro); padrao: acha sozinho")
    o.add_argument("--saida", default=str(AQUI), help="onde ficam o .sql, o inventario e o cache")
    o.add_argument("--saida-sql", default=None)
    a = ap.parse_args(argv)

    saida = Path(a.saida)
    pastas = {"saida": saida, "cache": saida / "bdgd_cache"}
    a.saida_sql = a.saida_sql or str(saida / "gridsight_dados_aneel_30.sql")
    backend = achar_backend(a.backend)
    print(f"Pasta do backend: {backend}", flush=True)
    terrain = backend / "terrain"
    clutter = backend / "clutter"
    etapas = set(a.so) if a.so else {"bdgd", "relevo", "arvores"}
    if a.pular_relevo:
        etapas.discard("relevo")
    if a.pular_arvores:
        etapas.discard("arvores")
    if a.listar:
        etapa_bdgd(a, pastas)
        return 0

    ativos = cands = None
    if a.bbox:
        etapas.discard("bdgd")
    elif "bdgd" in etapas:
        r = etapa_bdgd(a, pastas)
        if r:
            ativos, cands = r
    elif etapas & {"relevo", "arvores"}:
        ativos, cands = carregar_checkpoints(pastas["cache"])
        if not (ativos or cands):
            sys.exit("Nao ha dados processados ainda (bdgd_cache/ok_*.json). Rode a etapa 'bdgd' primeiro, ou use --bbox.")

    if "relevo" in etapas:
        if a.bbox:
            nomes = ladrilhos_bbox(*a.bbox)
        else:
            nomes = ladrilhos_relevo([(x[3], x[4]) for x in (ativos or []) + (cands or [])], a.margem_relevo_km)
        etapa_relevo(nomes, terrain, a.completo)

    if "arvores" in etapas:
        if a.bbox:
            la0, lo0, la1, lo1 = a.bbox
            passo = TILE_DEG
            pts = []
            la = min(la0, la1)
            while la <= max(la0, la1) + 1e-9:
                lo = min(lo0, lo1)
                while lo <= max(lo0, lo1) + 1e-9:
                    pts.append((la, lo, 1))
                    lo += passo
                la += passo
            grupos = {"regiao (bbox)": pts}
            a.raio_km = 0.0
            a.max_ladrilhos = 0
        else:
            grupos = {}
            for x in cands or []:
                peso = 20 if x[2] == "Subestação" else 1
                grupos.setdefault(x[5], []).append((x[3], x[4], peso))
        etapa_arvores(grupos, clutter, a)

    print("\nPronto. Rode o .sql no Workbench (banco %s) e reinicie o backend." % BANCO if "bdgd" in etapas else "\nPronto.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
