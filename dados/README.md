# GridSight - dados

Um script so, `gridsight_dados.py`, que baixa e prepara tudo que o GridSight precisa:

1. **Distribuidoras**: descobre no portal da ANEEL e baixa a BDGD das 30 principais.
2. **Ativos e candidatos**: gera o SQL (`asset` e `candidate_site`) com os mesmos criterios do banco atual.
3. **Relevo**: baixa os ladrilhos SRTM (.hgt, ~90 m) para `backend/terrain`.
4. **Arvores e predios**: baixa do OpenStreetMap, no formato do cache do backend, para `backend/clutter`.

## Como usar

Na pasta `dados`, no PowerShell:

```
py -m pip install -r requirements.txt     # so na primeira vez
py gridsight_dados.py --listar            # mostra o que a ANEEL tem e o que seria baixado
py gridsight_dados.py --max 2             # teste com 2 distribuidoras
py gridsight_dados.py                     # faz tudo, com as 30 principais
```

Ou de dois cliques em `rodar.bat`. Depois: rode o `.sql` no MySQL Workbench (banco `tecsys_gateway`) e reinicie o backend.

Pode interromper e rodar de novo: o que ja foi baixado ou processado e pulado.

## Pastas

```
GridSight/
  dados/                      <- este script
    gridsight_dados.py
    gridsight_dados_aneel_30.sql   (gerado)
    inventario_distribuidoras.csv  (gerado)
    bdgd_cache/                    (gerado: resultado de cada distribuidora)
  backend/
    terrain/                  <- relevo (.hgt)
    clutter/                  <- arvores e predios (t_<i>_<j>_v2.bin)
```

## Parametros (os mesmos do backend e do banco)

| O que | Valor |
|---|---|
| Ativos | UCAT completo + UCMT com 1000 por distribuidora, so `SIT_ATIV = 'AT'` |
| Candidatos | Subestacoes e chaves/religadores completos + 1500 transformadores por distribuidora |
| Relevo | SRTM ~90 m (1201x1201), ladrilhos de 1 grau, margem de 10 km |
| Arvores e predios | Ladrilho de 0,05 grau, celula de 0,0002 grau; mata = 15 m; predio = `height`, ou andares x 3,2 m, ou 8 m |
| Faixa de arvores e predios | 5 km ao redor dos candidatos, ate 400 ladrilhos por distribuidora |

## Opcoes mais usadas

| Opcao | Para que serve |
|---|---|
| `--listar` | so mostra o que seria baixado |
| `--max N` | processa so N distribuidoras (teste) |
| `--distribuidoras cemig light 390` | escolhe por nome ou codigo ANEEL |
| `--top N` / `--todas` | as N maiores / todas (centenas de GB!) |
| `--so bdgd` / `relevo` / `arvores` | roda so uma etapa |
| `--pular-relevo` / `--pular-arvores` | pula uma etapa |
| `--raio-km 5` / `--max-ladrilhos 400` | faixa de arvores e predios (0 = sem limite) |
| `--bbox LAT_MIN LON_MIN LAT_MAX LON_MAX` | relevo e arvores so de uma regiao |
| `--completo` | relevo na resolucao original (~30 m, ~25 MB por ladrilho) |
| `--pasta C:\bdgd` | usa .zip/.gdb que voce ja baixou a mao |
| `--urls links.txt` | um link .zip por linha |
| `--manter` | nao apaga os .zip depois de usar |

## Cuidados

- Reserve ~10 GB livres: cada BDGD tem varios GB (o .zip e apagado depois de usado).
- Arvores e predios podem levar horas: o Overpass publico tem limite e o script espera 1,5 s entre pedidos.
- Se uma distribuidora aparecer como "falta" no `--listar`, use `--distribuidoras` ou consulte o `inventario_distribuidoras.csv`.
- Se a ANEEL mudar o endereco do portal, baixe os .zip a mao e use `--pasta`.
