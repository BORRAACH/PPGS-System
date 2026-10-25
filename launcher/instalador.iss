; Instalador do Sistema de Pedidos (Inno Setup 6). Gerado pelo workflow de
; release; para rodar à mão: iscc /DVersao=v1.0.0 launcher\instalador.iss
; depois de scripts/montar_instalacao.py.
;
; Instala POR USUÁRIO (sem administrador) em %LOCALAPPDATA%\Programs: o
; bootstrap precisa gravar versoes\ ao atualizar, e uma pasta em Program Files
; exigiria elevação a cada atualização. A proteção contra adulteração é a
; assinatura dos pacotes, não o bloqueio de escrita.

#ifndef Versao
  #define Versao "0.0.0"
#endif

[Setup]
AppId={{PizzariaSistema-8F2C1D}
AppName=Sistema de Pedidos
AppVersion={#Versao}
DefaultDirName={localappdata}\Programs\PizzariaSistema
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist-instalador
OutputBaseFilename=Instalar-SistemaDePedidos
Compression=lzma2
SolidCompression=yes
UninstallDisplayName=Sistema de Pedidos

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
; O que muda quando o instalador muda: sempre sobrescreve.
Source: "..\dist-instalacao\SistemaDePedidos.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist-instalacao\lib\*"; DestDir: "{app}\lib"; Flags: ignoreversion recursesubdirs
; O que o bootstrap mantém sozinho (atualizações): só na primeira instalação,
; senão reinstalar o programa voltaria o sistema para a versão do instalador.
Source: "..\dist-instalacao\runtime\*"; DestDir: "{app}\runtime"; Flags: onlyifdoesntexist recursesubdirs
Source: "..\dist-instalacao\versoes\*"; DestDir: "{app}\versoes"; Flags: onlyifdoesntexist recursesubdirs
Source: "..\dist-instalacao\atual.json"; DestDir: "{app}"; Flags: onlyifdoesntexist

[Icons]
Name: "{autodesktop}\Sistema de Pedidos"; Filename: "{app}\SistemaDePedidos.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\Sistema de Pedidos"; Filename: "{app}\SistemaDePedidos.exe"; WorkingDir: "{app}"

[Run]
Filename: "{app}\runtime\python.exe"; Parameters: """{app}\lib\bootstrap.py"" --migrar-de ""{code:PastaAntiga}"""; Flags: runhidden; Check: TemPastaAntiga; StatusMsg: "Copiando os dados da instalação antiga..."
Filename: "{app}\SistemaDePedidos.exe"; Description: "Abrir o Sistema de Pedidos"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; versoes\ e runtime\ são criadas depois da instalação; os DADOS (pedidos etc.)
; ficam em %LOCALAPPDATA%\PizzariaSistema e NÃO são apagados de propósito.
Type: filesandordirs; Name: "{app}\versoes"
Type: filesandordirs; Name: "{app}\runtime"
Type: filesandordirs; Name: "{app}\runtime.novo"
Type: filesandordirs; Name: "{app}\runtime.antigo"
Type: files; Name: "{app}\atual.json"

[Code]
var
  PaginaAntiga: TInputDirWizardPage;

procedure InitializeWizard;
begin
  PaginaAntiga := CreateInputDirPage(wpSelectDir,
    'Instalação antiga (opcional)',
    'Trazer os dados de quem já usava o sistema',
    'Se o sistema era aberto rodando o main.py, escolha a pasta dele para copiar pedidos, cardápio e configurações. ' +
    'Deixe vazio para começar do zero.',
    False, '');
  PaginaAntiga.Add('');
end;

function PastaAntiga(Param: String): String;
begin
  Result := PaginaAntiga.Values[0];
end;

function TemPastaAntiga: Boolean;
begin
  Result := Trim(PaginaAntiga.Values[0]) <> '';
end;
