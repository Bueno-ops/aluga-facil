# Sobe o servidor local + tunel HTTPS e atualiza o QR code de instalacao.
#
# Uso (duplo clique em "abrir-no-celular.bat" ou):
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\abrir-no-celular.ps1"
#
# O que faz:
#   1. inicia o servidor local em modo rede (porta 8099)
#   2. abre um tunel gratuito do Cloudflare (link https publico temporario)
#   3. gera o QR code do link temporario em qrcode-tunel.png
#   4. atualiza o endereco dentro de instalar.html
#   5. abre a pagina de instalacao no navegador
#
# Para encerrar tudo, rode: .\parar-tunel.ps1

param(
    [int]$Porta = 8099,
    [switch]$SemNavegador
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cloudflared = Join-Path $Raiz 'ferramentas\cloudflared.exe'
$LogTunel = Join-Path $env:TEMP 'aluga-facil-tunel.log'
$LogServidor = Join-Path $env:TEMP 'aluga-facil-servidor.log'

Write-Host ''
Write-Host ' ALUGA FACIL - abrir no celular' -ForegroundColor Cyan
Write-Host ' ---------------------------------------------' -ForegroundColor DarkGray

if (-not (Test-Path -LiteralPath $Cloudflared)) {
    throw "cloudflared.exe nao encontrado em ferramentas\. Baixe em https://github.com/cloudflare/cloudflared/releases"
}

# --- 1. Servidor local -------------------------------------------------------
$servidorAtivo = $false
try {
    $teste = Invoke-WebRequest -Uri ("http://localhost:$Porta/app.html") -UseBasicParsing -TimeoutSec 3
    if ($teste.StatusCode -eq 200) { $servidorAtivo = $true }
} catch { $servidorAtivo = $false }

if ($servidorAtivo) {
    Write-Host ' [1/4] Servidor local ja esta rodando na porta ' -NoNewline
    Write-Host $Porta -ForegroundColor Green
} else {
    Write-Host ' [1/4] Iniciando servidor local...' -NoNewline
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $Raiz 'servidor-local.ps1') + '"'), '-Porta', $Porta, '-RedeLocal', '-SemNavegador') `
        -WindowStyle Hidden `
        -RedirectStandardOutput $LogServidor `
        -RedirectStandardError ($LogServidor + '.err')
    $ok = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 400
        try {
            $r = Invoke-WebRequest -Uri ("http://localhost:$Porta/app.html") -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $ok = $true; break }
        } catch { }
    }
    if ($ok) { Write-Host ' OK' -ForegroundColor Green }
    else { throw "O servidor nao respondeu na porta $Porta. Veja $LogServidor" }
}

# --- 2. Tunel HTTPS ----------------------------------------------------------
Write-Host ' [2/4] Abrindo tunel HTTPS (pode levar alguns segundos)...' -NoNewline
if (Test-Path -LiteralPath $LogTunel) { Remove-Item -LiteralPath $LogTunel -Force -ErrorAction SilentlyContinue }

Get-Process -Name 'cloudflared' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Process -FilePath $Cloudflared `
    -ArgumentList @('tunnel', '--url', ("http://localhost:$Porta"), '--no-autoupdate') `
    -WindowStyle Hidden `
    -RedirectStandardError $LogTunel `
    -RedirectStandardOutput ($LogTunel + '.out')

$urlPublica = $null
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 700
    if (Test-Path -LiteralPath $LogTunel) {
        $texto = Get-Content -LiteralPath $LogTunel -Raw -ErrorAction SilentlyContinue
        if ($texto -match '(https://[a-z0-9-]+\.trycloudflare\.com)') {
            $urlPublica = $Matches[1]
            break
        }
    }
}
if (-not $urlPublica) { throw "Nao foi possivel obter o link do tunel. Veja $LogTunel" }
Write-Host ' OK' -ForegroundColor Green

$urlApp = $urlPublica + '/app.html'
$urlInstalar = $urlPublica + '/instalar.html'

# --- 3. QR codes -------------------------------------------------------------
Write-Host ' [3/4] Gerando QR codes...' -NoNewline
$arquivoQr = Join-Path $Raiz 'qrcode-tunel.png'
$arquivoQrLocal = Join-Path $Raiz 'qrcode-instalar.png'
$versao = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
    Sort-Object -Property SkipAsSource, InterfaceIndex |
    Select-Object -First 1).IPAddress

function New-QrCode {
    param([string]$Texto, [string]$Destino)
    $api = 'https://api.qrserver.com/v1/create-qr-code/?size=700x700&margin=24&format=png&data=' + [uri]::EscapeDataString($Texto)
    Invoke-WebRequest -Uri $api -OutFile $Destino -UseBasicParsing -TimeoutSec 30
}

try {
    New-QrCode -Texto $urlApp -Destino $arquivoQr
    if ($ip) { New-QrCode -Texto ("http://" + $ip + ":" + $Porta + "/app.html") -Destino $arquivoQrLocal }
    Write-Host ' OK' -ForegroundColor Green
} catch {
    Write-Host ' falhou (mantidos os QR anteriores)' -ForegroundColor Yellow
}

# --- 4. Atualiza a pagina de instalacao --------------------------------------
Write-Host ' [4/4] Atualizando pagina de instalacao...' -NoNewline
$pagina = Join-Path $Raiz 'instalar.html'
if (Test-Path -LiteralPath $pagina) {
    $conteudo = [System.IO.File]::ReadAllText($pagina, [System.Text.Encoding]::UTF8)

    # Link HTTPS novo (o tunel muda de endereco a cada execucao)
    $conteudo = [regex]::Replace($conteudo, 'https://[a-z0-9-]+\.trycloudflare\.com/app\.html', ($urlPublica + '/app.html'))

    # Link da rede local acompanha o IP atual do computador
    if ($ip) {
        $conteudo = [regex]::Replace($conteudo, 'http://\d{1,3}(?:\.\d{1,3}){3}:\d+/app\.html', ("http://" + $ip + ":" + $Porta + "/app.html"))
    }

    # Evita que o service worker mostre um QR antigo do cache
    $conteudo = [regex]::Replace($conteudo, 'qrcode-instalar\.png(\?v=\d+)?', ('qrcode-instalar.png?v=' + $versao))

    [System.IO.File]::WriteAllText($pagina, $conteudo, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ' OK' -ForegroundColor Green
} else {
    Write-Host ' instalar.html nao encontrado' -ForegroundColor Yellow
}

# --- Resumo ------------------------------------------------------------------
Write-Host ''
Write-Host ' Pronto! Abra no celular:' -ForegroundColor Green
Write-Host ('   Link fixo (sempre disponivel): https://bueno-ops.github.io/aluga-facil/app.html') -ForegroundColor White
Write-Host ('   Tunel temporario (agora):      ' + $urlApp) -ForegroundColor DarkGray
if ($ip) {
    Write-Host ('   Rede local (mesma Wi-Fi):      http://' + $ip + ':' + $Porta + '/app.html') -ForegroundColor DarkGray
}
Write-Host ('   QR code: ' + $arquivoQr) -ForegroundColor DarkGray
Write-Host ''
Write-Host ' Deixe esta janela e o tunel abertos enquanto usar no celular.' -ForegroundColor Yellow
Write-Host ' Para encerrar: .\parar-tunel.ps1' -ForegroundColor Yellow
Write-Host ''

if (-not $SemNavegador) {
    Start-Process -FilePath ('http://localhost:' + $Porta + '/instalar.html')
}
