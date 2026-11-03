# Servidor local do Aluga Facil
# Uso: clique duas vezes em "abrir-app.bat" ou rode:
#   powershell -NoProfile -ExecutionPolicy Bypass -File ".\servidor-local.ps1"
# Serve a pasta do projeto em http://localhost:8099 (necessario para o PWA:
# service worker e instalacao so funcionam em http/https).
#
# Implementado com TcpListener para nao exigir privilegios de administrador.

param(
    [int]$Porta = 8099,
    [switch]$SemNavegador,
    [switch]$RedeLocal
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$RaizSep = $Raiz.TrimEnd([char]'\') + '\'

$mimes = @{
    ".html"  = "text/html; charset=utf-8"
    ".htm"   = "text/html; charset=utf-8"
    ".js"    = "application/javascript; charset=utf-8"
    ".json"  = "application/json; charset=utf-8"
    ".css"   = "text/css; charset=utf-8"
    ".svg"   = "image/svg+xml"
    ".png"   = "image/png"
    ".jpg"   = "image/jpeg"
    ".jpeg"  = "image/jpeg"
    ".webp"  = "image/webp"
    ".ico"   = "image/x-icon"
    ".woff"  = "font/woff"
    ".woff2" = "font/woff2"
    ".txt"   = "text/plain; charset=utf-8"
    ".md"    = "text/markdown; charset=utf-8"
    ".webmanifest" = "application/manifest+json"
}

function Obter-Mime([string]$caminho) {
    $ext = [System.IO.Path]::GetExtension($caminho).ToLowerInvariant()
    if ($mimes.ContainsKey($ext)) { return $mimes[$ext] }
    return "application/octet-stream"
}

function Enviar-Resposta($stream, [int]$codigo, [string]$tipo, [byte[]]$corpo, [bool]$semCorpo = $false) {
    $motivo = switch ($codigo) {
        200 { "OK" }
        404 { "Not Found" }
        405 { "Method Not Allowed" }
        500 { "Internal Server Error" }
        default { "OK" }
    }
    $cabecalho = "HTTP/1.1 $codigo $motivo`r`n" +
                 "Content-Type: $tipo`r`n" +
                 "Content-Length: $($corpo.Length)`r`n" +
                 "Cache-Control: no-store`r`n" +
                 "X-Content-Type-Options: nosniff`r`n" +
                 "Connection: close`r`n`r`n"
    $bytesCabecalho = [System.Text.Encoding]::ASCII.GetBytes($cabecalho)
    $stream.Write($bytesCabecalho, 0, $bytesCabecalho.Length)
    if (-not $semCorpo -and $corpo.Length -gt 0) {
        $stream.Write($corpo, 0, $corpo.Length)
    }
    $stream.Flush()
}

$enderecoIp = if ($RedeLocal) { [System.Net.IPAddress]::Any } else { [System.Net.IPAddress]::Loopback }

$ouvinte = $null
for ($p = $Porta; $p -lt ($Porta + 20); $p++) {
    try {
        $teste = [System.Net.Sockets.TcpListener]::new($enderecoIp, $p)
        $teste.Start()
        $ouvinte = $teste
        $Porta = $p
        break
    } catch { }
}

if ($null -eq $ouvinte) {
    Write-Host "Nao foi possivel abrir uma porta livre perto de $Porta." -ForegroundColor Red
    exit 1
}

$url = "http://localhost:$Porta/app.html"
Write-Host ""
Write-Host "  ALUGA FACIL - servidor local" -ForegroundColor Green
Write-Host "  Pasta:    $Raiz"
Write-Host "  Endereco: $url"
if ($RedeLocal) {
    $ipLocal = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.IPAddressToString -notlike '127.*' } |
        Select-Object -First 1
    if ($null -ne $ipLocal) {
        Write-Host "  Celular:  http://$($ipLocal.IPAddressToString):$Porta/app.html" -ForegroundColor Cyan
        Write-Host "            (mesma rede Wi-Fi; libere o PowerShell no firewall se pedir)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Dica:     use -RedeLocal para acessar pelo celular na mesma Wi-Fi" -ForegroundColor DarkGray
}
Write-Host "  Encerrar: Ctrl+C"
Write-Host ""

if (-not $SemNavegador) {
    try { Start-Process $url | Out-Null } catch { }
}

try {
    while ($true) {
        $cliente = $ouvinte.AcceptTcpClient()
        $stream = $null
        try {
            $cliente.ReceiveTimeout = 5000
            $stream = $cliente.GetStream()
            $stream.ReadTimeout = 5000

            $buffer = New-Object byte[] 8192
            $texto = New-Object System.Text.StringBuilder
            do {
                $lidos = $stream.Read($buffer, 0, $buffer.Length)
                if ($lidos -le 0) { break }
                [void]$texto.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $lidos))
            } while ($texto.ToString().IndexOf("`r`n`r`n") -lt 0)

            $requisicao = $texto.ToString()
            $primeiraLinha = ($requisicao -split "`r`n")[0]
            $partes = $primeiraLinha -split " "
            $metodo = if ($partes.Count -ge 1) { $partes[0].ToUpperInvariant() } else { "" }
            $alvo = if ($partes.Count -ge 2) { $partes[1] } else { "/" }

            if ($metodo -ne "GET" -and $metodo -ne "HEAD") {
                $corpo = [System.Text.Encoding]::UTF8.GetBytes("Metodo nao permitido")
                Enviar-Resposta $stream 405 "text/plain; charset=utf-8" $corpo
                continue
            }

            $caminhoUrl = $alvo.Split("?")[0].Split("#")[0]
            try { $caminhoUrl = [System.Uri]::UnescapeDataString($caminhoUrl) } catch { $caminhoUrl = "/" }
            if ($caminhoUrl -eq "/" -or $caminhoUrl -eq "") { $caminhoUrl = "/app.html" }

            $relativo = $caminhoUrl.TrimStart("/").Replace("/", [System.IO.Path]::DirectorySeparatorChar)
            $arquivo = [System.IO.Path]::GetFullPath((Join-Path $Raiz $relativo))

            if (-not $arquivo.StartsWith($RaizSep, [System.StringComparison]::OrdinalIgnoreCase)) {
                $corpo = [System.Text.Encoding]::UTF8.GetBytes("Acesso negado")
                Enviar-Resposta $stream 404 "text/plain; charset=utf-8" $corpo ($metodo -eq "HEAD")
                Write-Host ("404 " + $caminhoUrl) -ForegroundColor Yellow
                continue
            }

            if (Test-Path -LiteralPath $arquivo -PathType Container) {
                $arquivo = Join-Path $arquivo "index.html"
            }

            if (Test-Path -LiteralPath $arquivo -PathType Leaf) {
                $corpo = [System.IO.File]::ReadAllBytes($arquivo)
                $tipo = Obter-Mime $arquivo
                Enviar-Resposta $stream 200 $tipo $corpo ($metodo -eq "HEAD")
                Write-Host ("200 " + $caminhoUrl)
            } else {
                $corpo = [System.Text.Encoding]::UTF8.GetBytes("<h1>404</h1><p>Arquivo nao encontrado: " + $caminhoUrl + "</p>")
                Enviar-Resposta $stream 404 "text/html; charset=utf-8" $corpo ($metodo -eq "HEAD")
                Write-Host ("404 " + $caminhoUrl) -ForegroundColor Yellow
            }
        } catch {
            if ($null -ne $stream) {
                try {
                    $corpo = [System.Text.Encoding]::UTF8.GetBytes("Erro interno do servidor")
                    Enviar-Resposta $stream 500 "text/plain; charset=utf-8" $corpo
                } catch { }
            }
        } finally {
            if ($null -ne $cliente) { $cliente.Close() }
        }
    }
}
finally {
    if ($null -ne $ouvinte) { $ouvinte.Stop() }
}
