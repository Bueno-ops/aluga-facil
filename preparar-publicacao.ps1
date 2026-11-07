# Gera a pasta "dist" com apenas os arquivos do site (sem scripts e sem o cloudflared).
# Use a pasta dist para arrastar no Netlify Drop / Cloudflare Pages, ou publique no GitHub Pages.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File ".\preparar-publicacao.ps1"

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dist = Join-Path $Raiz 'dist'

if (Test-Path -LiteralPath $Dist) {
    Remove-Item -LiteralPath $Dist -Recurse -Force
}
New-Item -ItemType Directory -Path $Dist | Out-Null

$arquivos = @(
    'app.html',
    'index.html',
    'instalar.html',
    'manifest.json',
    'sw.js',
    'robots.txt',
    'icon.svg',
    'qrcode-fixo.png',
    'qrcode-instalar.png',
    'qrcode-atualizar.png'
)
$arquivos += Get-ChildItem -LiteralPath $Raiz -Filter 'icon-*.png' | Select-Object -ExpandProperty Name

$copiados = 0
foreach ($nome in $arquivos) {
    $origem = Join-Path $Raiz $nome
    if (Test-Path -LiteralPath $origem) {
        Copy-Item -LiteralPath $origem -Destination (Join-Path $Dist $nome)
        $copiados++
    }
}

$tamanho = [math]::Round(((Get-ChildItem -LiteralPath $Dist -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 2)

Write-Host ''
Write-Host ' Publicacao preparada' -ForegroundColor Green
Write-Host (' Arquivos: ' + $copiados + ' | Tamanho: ' + $tamanho + ' MB')
Write-Host (' Pasta:    ' + $Dist)
Write-Host ''
Write-Host ' Netlify Drop:  https://app.netlify.com/drop  (arraste a pasta dist)' -ForegroundColor Cyan
Write-Host ' Cloudflare:    Workers & Pages > Create > Pages > Upload assets' -ForegroundColor Cyan
Write-Host ' GitHub Pages:  envie o repositorio e ative em Settings > Pages' -ForegroundColor Cyan
Write-Host ''
