# Generate store-specific encodings and a vector-based feature graphic.
# This leaves the Android launcher assets and original brand images untouched.
param([switch] $IconOnly)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$storeRoot = Join-Path $projectRoot 'store-assets'
$null = New-Item -ItemType Directory -Force -Path $storeRoot

function Color([string] $Value) { [System.Drawing.ColorTranslator]::FromHtml($Value) }
function Rounded-Rectangle([float] $X, [float] $Y, [float] $Width, [float] $Height, [float] $Radius) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

$source = [System.Drawing.Bitmap]::new((Join-Path $projectRoot 'FitteryLogo_512x512.png'))
$icon = [System.Drawing.Bitmap]::new(512, 512, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$iconGraphics = [System.Drawing.Graphics]::FromImage($icon)
try {
    if ($source.Width -ne 512 -or $source.Height -ne 512) { throw 'Expected the original 512 x 512 icon.' }
    $iconGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $iconGraphics.DrawImageUnscaled($source, 0, 0)
    $icon.Save((Join-Path $storeRoot 'app-icon-512.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $iconGraphics.Dispose(); $icon.Dispose(); $source.Dispose()
}

if ($IconOnly) {
    Write-Output 'Generated 32-bit store icon.'
    return
}

$svg = @'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500" role="img" aria-labelledby="title desc">
  <title id="title">Fittery — know your battery</title>
  <desc id="desc">Live readings, local history and charging alerts, with an illustrated battery on a teal background.</desc>
  <defs>
    <linearGradient id="background" x2="1" y2="1"><stop stop-color="#073F46"/><stop offset="1" stop-color="#092A33"/></linearGradient>
    <linearGradient id="charge" x2="1" y2="1"><stop stop-color="#45E4C8"/><stop offset="1" stop-color="#B7F26B"/></linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#background)"/>
  <circle cx="830" cy="250" r="186" fill="#43E4C2" opacity=".035"/>
  <circle cx="830" cy="250" r="148" fill="none" stroke="#58D8C2" opacity=".11"/>
  <g font-family="Segoe UI,Arial,sans-serif" fill="#F2FCFA">
    <text x="72" y="104" font-size="25" font-weight="600">Fittery</text>
    <text x="68" y="205" font-size="64" font-weight="700">Know your</text>
    <text x="68" y="279" font-size="64" font-weight="700">battery.</text>
    <g font-size="22" fill="#B8D9D7">
      <text x="72" y="342">Live readings. Local history.</text>
      <text x="72" y="375">Charging alerts you control.</text>
    </g>
  </g>
  <rect x="646" y="179" width="270" height="154" rx="30" fill="#0B3940" stroke="#6CDCC4" stroke-width="4"/>
  <rect x="923" y="227" width="12" height="58" rx="5" fill="#6CDCC4"/>
  <g fill="url(#charge)">
    <rect x="665" y="198" width="49" height="116" rx="10"/>
    <rect x="726" y="198" width="49" height="116" rx="10"/>
    <rect x="787" y="198" width="49" height="116" rx="10"/>
  </g>
  <rect x="848" y="198" width="49" height="116" rx="10" fill="#6CDCC4" opacity=".13"/>
  <path d="M72 426H952" stroke="#39727A" stroke-width="1"/>
</svg>
'@
[IO.File]::WriteAllText((Join-Path $storeRoot 'feature-graphic.svg'), $svg, [Text.UTF8Encoding]::new($false))

# Render the same vector layout with GDI+ so no external renderer is required.
$bitmap = [System.Drawing.Bitmap]::new(1024, 500, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$resources = [Collections.Generic.List[IDisposable]]::new()
function Keep([IDisposable] $Resource) { $resources.Add($Resource); return $Resource }
try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $background = Keep ([System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Rectangle]::new(0, 0, 1024, 500), (Color '#073F46'), (Color '#092A33'), 45))
    $graphics.FillRectangle($background, 0, 0, 1024, 500)
    $halo = Keep ([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(9, 67, 228, 194)))
    $graphics.FillEllipse($halo, 644, 64, 372, 372)
    $ring = Keep ([System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(28, 88, 216, 194), 1))
    $graphics.DrawEllipse($ring, 682, 102, 296, 296)

    $white = Keep ([System.Drawing.SolidBrush]::new((Color '#F2FCFA')))
    $muted = Keep ([System.Drawing.SolidBrush]::new((Color '#B8D9D7')))
    $brand = Keep ([System.Drawing.Font]::new('Segoe UI', 25, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel))
    $headline = Keep ([System.Drawing.Font]::new('Segoe UI', 64, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel))
    $body = Keep ([System.Drawing.Font]::new('Segoe UI', 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel))
    $graphics.DrawString('Fittery', $brand, $white, 68, 77)
    $graphics.DrawString('Know your', $headline, $white, 61, 138)
    $graphics.DrawString('battery.', $headline, $white, 61, 212)
    $graphics.DrawString('Live readings. Local history.', $body, $muted, 68, 318)
    $graphics.DrawString('Charging alerts you control.', $body, $muted, 68, 351)

    $case = Keep (Rounded-Rectangle 646 179 270 154 30)
    $caseFill = Keep ([System.Drawing.SolidBrush]::new((Color '#0B3940')))
    $outline = Keep ([System.Drawing.Pen]::new((Color '#6CDCC4'), 4))
    $graphics.FillPath($caseFill, $case)
    $graphics.DrawPath($outline, $case)
    $terminal = Keep (Rounded-Rectangle 923 227 12 58 5)
    $mint = Keep ([System.Drawing.SolidBrush]::new((Color '#6CDCC4')))
    $graphics.FillPath($mint, $terminal)
    foreach ($x in @(665, 726, 787)) {
        $cell = Keep (Rounded-Rectangle $x 198 49 116 10)
        $charge = Keep ([System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Rectangle]::new($x, 198, 49, 116), (Color '#45E4C8'), (Color '#B7F26B'), 45))
        $graphics.FillPath($charge, $cell)
    }
    $empty = Keep (Rounded-Rectangle 848 198 49 116 10)
    $emptyFill = Keep ([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(33, 108, 220, 196)))
    $graphics.FillPath($emptyFill, $empty)
    $rule = Keep ([System.Drawing.Pen]::new((Color '#39727A'), 1))
    $graphics.DrawLine($rule, 72, 426, 952, 426)
    $bitmap.Save((Join-Path $storeRoot 'feature-graphic-1024x500.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    foreach ($resource in $resources) { $resource.Dispose() }
    $graphics.Dispose(); $bitmap.Dispose()
}
Write-Output 'Generated 32-bit store icon, editable feature SVG, and opaque 1024 x 500 feature PNG.'
