# Gera os icones PNG do Aluga Facil usando System.Drawing.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File ".\gerar-icones.ps1"
# Sao gerados os tamanhos do manifest + as versoes maskable (Android).

Add-Type -AssemblyName System.Drawing

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path

function New-Icone {
    param(
        [int]$Tamanho,
        [string]$Nome,
        [bool]$Maskable = $false
    )

    $bmp = [System.Drawing.Bitmap]::new($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $inicio = [System.Drawing.ColorTranslator]::FromHtml('#183C8F')
    $fim = [System.Drawing.ColorTranslator]::FromHtml('#0A1C59')
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Point]::new(0, 0),
        [System.Drawing.Point]::new($Tamanho, $Tamanho),
        $inicio,
        $fim
    )

    if ($Maskable) {
        # Fundo cheio (a plataforma aplica a mascara) e conteudo na zona segura
        $g.FillRectangle($brush, 0, 0, $Tamanho, $Tamanho)
        $escalaConteudo = 0.70
    } else {
        $raio = [double]$Tamanho * 0.22
        $diametro = $raio * 2
        $borda = $Tamanho - 1
        $caminho = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $caminho.AddArc(0, 0, $diametro, $diametro, 180, 90)
        $caminho.AddArc($borda - $diametro, 0, $diametro, $diametro, 270, 90)
        $caminho.AddArc($borda - $diametro, $borda - $diametro, $diametro, $diametro, 0, 90)
        $caminho.AddArc(0, $borda - $diametro, $diametro, $diametro, 90, 90)
        $caminho.CloseFigure()
        $g.FillPath($brush, $caminho)
        $caminho.Dispose()
        $escalaConteudo = 1.0
    }

    # Circulos decorativos
    $brancoSuave = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(26, 255, 255, 255))
    $pretoSuave = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(18, 0, 0, 0))
    $g.FillEllipse($brancoSuave, [int]($Tamanho * 0.70), [int](-$Tamanho * 0.14), [int]($Tamanho * 0.55), [int]($Tamanho * 0.55))
    $g.FillEllipse($pretoSuave, [int](-$Tamanho * 0.18), [int]($Tamanho * 0.72), [int]($Tamanho * 0.55), [int]($Tamanho * 0.55))

    # Conteudo desenhado em coordenadas 512x512
    $offset = ($Tamanho * (1 - $escalaConteudo)) / 2
    $escala = ($Tamanho * $escalaConteudo) / 512
    $g.TranslateTransform($offset, $offset)
    $g.ScaleTransform($escala, $escala)

    $caneta = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#F7CE46'), 28)
    $caneta.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $caneta.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $caneta.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    # Casa: telhado, paredes e porta (marca própria inspirada no segmento de obra)
    $g.DrawLines($caneta, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(118, 248),
        [System.Drawing.Point]::new(256, 138),
        [System.Drawing.Point]::new(394, 248)
    ))
    $g.DrawLines($caneta, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(160, 232),
        [System.Drawing.Point]::new(160, 382),
        [System.Drawing.Point]::new(352, 382),
        [System.Drawing.Point]::new(352, 232)
    ))
    $g.DrawLines($caneta, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(226, 382),
        [System.Drawing.Point]::new(226, 292),
        [System.Drawing.Point]::new(286, 292),
        [System.Drawing.Point]::new(286, 382)
    ))

    $destino = Join-Path $Raiz $Nome
    $bmp.Save($destino, [System.Drawing.Imaging.ImageFormat]::Png)

    $caneta.Dispose()
    $brancoSuave.Dispose()
    $pretoSuave.Dispose()
    $brush.Dispose()
    $g.Dispose()
    $bmp.Dispose()

    Write-Host "Gerado: $Nome"
}

$tamanhos = @(48, 72, 96, 128, 144, 152, 192, 256, 384, 512)
foreach ($t in $tamanhos) {
    New-Icone -Tamanho $t -Nome ("icon-{0}.png" -f $t)
}

New-Icone -Tamanho 192 -Nome "icon-maskable-192.png" -Maskable $true
New-Icone -Tamanho 512 -Nome "icon-maskable-512.png" -Maskable $true

Write-Host ""
Write-Host "Icones gerados em $Raiz" -ForegroundColor Green
