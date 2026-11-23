#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
baixar_relevo_gridsight.py - baixa o relevo (SRTM .hgt) das 5 distribuidoras do GridSight.

Só biblioteca padrão do Python (sem pip install). Fonte: cópia pública do SRTM na AWS
(sem login). Por padrão guarda versão LEVE (~90 m, ~2,8 MB por ladrilho, ~110 MB no total),
suficiente para enlaces de alguns km. Com --completo guarda a original de ~30 m (~25 MB cada).

USO (no seu computador, com internet), dentro da pasta do backend:

    python scripts/baixar_relevo_gridsight.py                  # os 38 ladrilhos dos seus dados, versão leve
    python scripts/baixar_relevo_gridsight.py --prioridade     # só os 10 mais usados (Grande SP + Vale do Paraíba)
    python scripts/baixar_relevo_gridsight.py --completo       # resolução original (mais pesado)
    python scripts/baixar_relevo_gridsight.py --bbox -23.4 -46.1 -23.0 -45.7   # só uma região (lat_min lon_min lat_max lon_max)

Os arquivos vão para ./terrain (pasta lida pelo backend). Já baixados são pulados.
Conferir depois: GET http://localhost:8080/api/coverage/terrain/status
"""
import argparse, array, gzip, math, os, sys, time, urllib.error, urllib.request

BASE = "https://elevation-tiles-prod.s3.amazonaws.com/skadi/"

# Ladrilhos que cobrem os ativos/candidatos das 5 distribuidoras (Enel SP, EDP SP, CPFL Paulista, CPFL Piratininga, Neoenergia Elektro)
PRIORIDADE = ["S26W049", "S24W047", "S23W048", "S24W048", "S24W046", "S23W046", "S22W048", "S22W049", "S21W050", "S23W047", "S23W049"]
TODOS = sorted(set(PRIORIDADE + [
    "S20W048", "S20W050", "S20W051", "S20W053", "S21W048", "S21W049", "S21W051", "S21W052", "S21W053",
    "S22W047", "S22W050", "S22W051", "S22W052", "S22W053", "S23W045", "S23W050", "S23W051", "S23W052", "S23W053", "S23W054",
    "S24W045", "S24W049", "S24W050", "S25W047", "S25W048", "S25W049", "S25W050", "S26W048"]))


def nome(lat, lon):
    return f"{'S' if lat < 0 else 'N'}{abs(lat):02d}{'W' if lon < 0 else 'E'}{abs(lon):03d}"


def por_bbox(a, b, c, d):
    out = []
    for la in range(math.floor(min(a, c)), math.floor(max(a, c)) + 1):
        for lo in range(math.floor(min(b, d)), math.floor(max(b, d)) + 1):
            out.append(nome(la, lo))
    return out


def leve(dados: bytes) -> bytes:
    """3601x3601 -> 1201x1201 (1 amostra a cada 3). Mantém o formato .hgt (int16 big-endian)."""
    n = 3601
    if len(dados) != n * n * 2:
        return dados  # já é 1201 (ou outro tamanho): guarda como veio
    arr = array.array("H")
    arr.frombytes(dados)               # só copia valores, a ordem dos bytes não muda
    out = array.array("H")
    for r in range(0, n, 3):
        out.extend(arr[r * n: (r + 1) * n: 3])
    return out.tobytes()


def baixar(nm, destino, completo, base):
    arq = os.path.join(destino, nm + ".hgt")
    if os.path.exists(arq) and os.path.getsize(arq) > 1_000_000:
        return "já existe"
    url = f"{base}{nm[:3]}/{nm}.hgt.gz"
    for tentativa in range(1, 4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "GridSight/1.0"}), timeout=90) as r:
                dados = gzip.decompress(r.read())
            dados = dados if completo else leve(dados)
            tmp = arq + ".part"
            with open(tmp, "wb") as f:
                f.write(dados)
            os.replace(tmp, arq)
            return f"ok ({len(dados) / 1e6:.1f} MB)"
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                return f"sem dado ({e.code}) - provavelmente oceano/fora da cobertura"
            err = f"HTTP {e.code}"
        except Exception as e:  # rede, gzip truncado...
            err = str(e)
        time.sleep(2 * tentativa)
    return f"FALHOU: {err}"


def main():
    ap = argparse.ArgumentParser(description="Baixa relevo SRTM para o GridSight.")
    ap.add_argument("--saida", default="terrain")
    ap.add_argument("--completo", action="store_true", help="resolução original ~30 m (cada ladrilho ~25 MB)")
    ap.add_argument("--prioridade", action="store_true", help="só os 10 ladrilhos mais usados")
    ap.add_argument("--bbox", nargs=4, type=float, metavar=("LAT_MIN", "LON_MIN", "LAT_MAX", "LON_MAX"))
    ap.add_argument("--base", default=BASE, help=argparse.SUPPRESS)
    a = ap.parse_args()

    lista = por_bbox(*a.bbox) if a.bbox else (PRIORIDADE if a.prioridade else TODOS)
    os.makedirs(a.saida, exist_ok=True)
    print(f"{len(lista)} ladrilho(s) -> {os.path.abspath(a.saida)}  ({'original ~30 m' if a.completo else 'leve ~90 m'})")
    falhas = 0
    for i, nm in enumerate(lista, 1):
        res = baixar(nm, a.saida, a.completo, a.base)
        falhas += res.startswith("FALHOU")
        print(f"[{i}/{len(lista)}] {nm}: {res}", flush=True)
    print("Concluído." if not falhas else f"Concluído com {falhas} falha(s): rode de novo, só os que faltam serão baixados.")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
