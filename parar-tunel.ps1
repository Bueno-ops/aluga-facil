# Encerra o servidor local e o tunel HTTPS do Aluga Facil.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File ".\parar-tunel.ps1"

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$encerrados = 0

$cloudflared = Get-Process -Name 'cloudflared' -ErrorAction SilentlyContinue
if ($cloudflared) {
    $cloudflared | Stop-Process -Force
    $encerrados += @($cloudflared).Count
}

$powershells = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*servidor-local.ps1*' }
foreach ($p in $powershells) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    $encerrados++
}

if ($encerrados -gt 0) {
    Write-Host ("Processos encerrados: " + $encerrados) -ForegroundColor Green
} else {
    Write-Host 'Nada rodando: servidor e tunel ja estavam parados.' -ForegroundColor Yellow
}
