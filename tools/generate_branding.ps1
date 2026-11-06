# Regenerate Android assets from the original logos in the project root.
# Run from PowerShell on Windows: .\tools\generate_branding.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$resRoot = Join-Path $projectRoot 'android/app/src/main/res'

function Write-ScaledImage {
    param(
        [System.Drawing.Image] $Source,
        [int] $CanvasSize,
        [int] $ImageSize,
        [string] $Path
    )
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    $bitmap = [System.Drawing.Bitmap]::new($CanvasSize, $CanvasSize)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $offset = [int](($CanvasSize - $ImageSize) / 2)
        $graphics.DrawImage($Source, $offset, $offset, $ImageSize, $ImageSize)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Read-AdaptiveForeground {
    # The supplied SVG wraps two embedded PNGs: a luminance mask and artwork.
    # Decode those layers with GDI+ so regeneration needs no external renderer.
    [xml] $svg = Get-Content -LiteralPath (Join-Path $projectRoot 'FitteryNoBG.svg') -Raw
    $images = $svg.SelectNodes('//*[local-name()="image"]')
    if ($images.Count -ne 2) { throw 'Expected artwork and mask images in FitteryNoBG.svg.' }
    $layers = [Collections.Generic.List[System.Drawing.Bitmap]]::new()
    try {
        foreach ($image in $images) {
            $data = $image.GetAttribute('href', 'http://www.w3.org/1999/xlink')
            $stream = [IO.MemoryStream]::new([Convert]::FromBase64String($data.Substring($data.IndexOf(',') + 1)))
            $decoded = $null
            try {
                $decoded = [System.Drawing.Bitmap]::new($stream)
                $layers.Add([System.Drawing.Bitmap]::new($decoded))
            } finally {
                if ($null -ne $decoded) { $decoded.Dispose() }
                $stream.Dispose()
            }
        }
        $mask = $layers[0]
        $artwork = $layers[1]
        if ($mask.Size -ne $artwork.Size) { throw 'SVG artwork and mask dimensions must match.' }
        $foreground = [System.Drawing.Bitmap]::new($artwork.Width, $artwork.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        for ($y = 0; $y -lt $artwork.Height; $y++) {
            for ($x = 0; $x -lt $artwork.Width; $x++) {
                $pixel = $artwork.GetPixel($x, $y)
                $maskPixel = $mask.GetPixel($x, $y)
                $luminance = 0.2126 * $maskPixel.R + 0.7152 * $maskPixel.G + 0.0722 * $maskPixel.B
                $alpha = [int][Math]::Round($pixel.A * $maskPixel.A * $luminance / (255.0 * 255.0))
                $foreground.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $pixel.R, $pixel.G, $pixel.B))
            }
        }
        return $foreground
    } finally {
        foreach ($layer in $layers) { $layer.Dispose() }
    }
}

function Get-VisibleRadius([System.Drawing.Bitmap] $Image) {
    $maxRadius = 0.0
    for ($y = 0; $y -lt $Image.Height; $y++) {
        for ($x = 0; $x -lt $Image.Width; $x++) {
            if ($Image.GetPixel($x, $y).A -gt 8) {
                $dx = $x - ($Image.Width - 1) / 2.0
                $dy = $y - ($Image.Height - 1) / 2.0
                $maxRadius = [Math]::Max($maxRadius, [Math]::Sqrt($dx * $dx + $dy * $dy))
            }
        }
    }
    if ($maxRadius -eq 0) { throw 'Brand artwork must contain visible pixels.' }
    return $maxRadius
}

$icon = [System.Drawing.Bitmap]::new((Join-Path $projectRoot 'FitteryLogo_512x512.png'))
$splash = [System.Drawing.Bitmap]::new((Join-Path $projectRoot 'FitteryTransparentSplash_512x512.png'))
$foreground = $null
try {
    foreach ($density in @{
        'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192
    }.GetEnumerator()) {
        Write-ScaledImage $icon $density.Value $density.Value (Join-Path $resRoot "mipmap-$($density.Key)/ic_launcher.png")
    }

    # Keep the transparent symbol inside the adaptive icon's 66dp safe circle,
    # with 1dp spare. The separate background fills every launcher mask.
    $foreground = Read-AdaptiveForeground
    $foregroundSize = [int][Math]::Floor($foreground.Width * (32 * 4) / (Get-VisibleRadius $foreground))
    Write-ScaledImage $foreground 432 $foregroundSize (Join-Path $resRoot 'drawable-xxxhdpi/ic_launcher_foreground.png')

    # Android 12 masks a 288dp splash canvas to a 192dp circle. Measure the
    # visible artwork so the entire symbol and wordmark fit, with 2dp spare.
    # Ignore the source's nearly invisible alpha fringe around the outer edges.
    $maxRadius = Get-VisibleRadius $splash
    $splashSize = [int][Math]::Floor($splash.Width * (94 * 4) / $maxRadius)
    Write-ScaledImage $splash 1152 $splashSize (Join-Path $resRoot 'drawable-xxxhdpi/splash_logo.png')
} finally {
    $icon.Dispose()
    $splash.Dispose()
    if ($null -ne $foreground) { $foreground.Dispose() }
}
Write-Output 'Generated launcher icons, adaptive foreground, and padded splash logo.'
