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

$icon = [System.Drawing.Bitmap]::new((Join-Path $projectRoot 'fittery_app_drawer_512.png'))
$splash = [System.Drawing.Bitmap]::new((Join-Path $projectRoot 'fittery500x500_splash.png'))
try {
    foreach ($density in @{
        'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192
    }.GetEnumerator()) {
        Write-ScaledImage $icon $density.Value $density.Value (Join-Path $resRoot "mipmap-$($density.Key)/ic_launcher.png")
    }

    # Adaptive layers are 108dp; fit the original icon into the inner 72dp.
    Write-ScaledImage $icon 432 288 (Join-Path $resRoot 'drawable-xxxhdpi/ic_launcher_foreground.png')

    # Android 12 masks a 288dp splash canvas to a 192dp circle. Measure the
    # visible artwork so the entire fish and wordmark fit, with 2dp spare.
    # Ignore the source's nearly invisible alpha fringe around the outer edges.
    $maxRadius = 0.0
    for ($y = 0; $y -lt $splash.Height; $y++) {
        for ($x = 0; $x -lt $splash.Width; $x++) {
            if ($splash.GetPixel($x, $y).A -gt 8) {
                $dx = $x - ($splash.Width - 1) / 2.0
                $dy = $y - ($splash.Height - 1) / 2.0
                $maxRadius = [Math]::Max($maxRadius, [Math]::Sqrt($dx * $dx + $dy * $dy))
            }
        }
    }
    $splashSize = [int][Math]::Floor($splash.Width * (94 * 4) / $maxRadius)
    Write-ScaledImage $splash 1152 $splashSize (Join-Path $resRoot 'drawable-xxxhdpi/splash_logo.png')
} finally {
    $icon.Dispose()
    $splash.Dispose()
}
Write-Output 'Generated launcher icons, adaptive foreground, and padded splash logo.'
