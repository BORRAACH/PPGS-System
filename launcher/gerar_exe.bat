@echo off
REM Gera o SistemaDePedidos.exe a partir de launcher\iniciar.py.
REM
REM Tem que rodar NO WINDOWS: o PyInstaller nao faz compilacao cruzada, entao
REM um .exe so pode ser gerado numa maquina Windows. So precisa ser feito de
REM novo se launcher\iniciar.py mudar -- o .exe e um atalho executavel, nao
REM leva o codigo do sistema dentro dele (ver o comentario no topo do .py).
REM
REM Uso: abra esta pasta no Explorador e de duplo clique, ou rode
REM   launcher\gerar_exe.bat
REM a partir da raiz do projeto.

setlocal
cd /d "%~dp0.."

echo.
echo === Gerando o executavel do Sistema de Pedidos ===
echo.

REM Prefere o Python do venv do projeto; senao usa o do sistema (py.exe existe
REM mesmo quando o python.exe nao esta no PATH).
set "PY=.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py -3"

echo [1/2] Garantindo o PyInstaller...
%PY% -m pip install --quiet --upgrade pyinstaller
if errorlevel 1 (
    echo.
    echo FALHOU ao instalar o PyInstaller. Confira a conexao com a internet.
    pause
    exit /b 1
)

echo [2/2] Empacotando...
REM --onefile     : um arquivo so, sem pasta de apoio
REM --noconsole   : sem a janela preta de console junto do app
REM --name        : nome que aparece para o usuario
REM Sem --add-data de proposito: o .exe NAO leva o sistema dentro dele. Ele so
REM acha o Python e roda o main.py que esta no disco, o que mantem a
REM auto-atualizacao por git funcionando (ver Config\atualizador.py).
%PY% -m PyInstaller ^
    --onefile ^
    --noconsole ^
    --name SistemaDePedidos ^
    --distpath . ^
    --workpath launcher\build ^
    --specpath launcher\build ^
    launcher\iniciar.py

if errorlevel 1 (
    echo.
    echo FALHOU ao gerar o executavel.
    pause
    exit /b 1
)

echo.
echo === Pronto ===
echo O arquivo SistemaDePedidos.exe foi criado na raiz do projeto.
echo.
echo Para colocar na Area de Trabalho, crie um ATALHO (botao direito no .exe
echo ^> Enviar para ^> Area de trabalho). Nao copie o .exe para fora da pasta:
echo ele procura o main.py ao lado dele.
echo.
pause
