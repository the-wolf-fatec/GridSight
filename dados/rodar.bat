@echo off
REM GridSight - baixa distribuidoras, ativos, candidatos, relevo, arvores e predios.
REM De dois cliques para fazer tudo (30 principais). Para outras opcoes, use o PowerShell:  py gridsight_dados.py --help
cd /d "%~dp0"
py -m pip install -r requirements.txt
py gridsight_dados.py %*
pause
