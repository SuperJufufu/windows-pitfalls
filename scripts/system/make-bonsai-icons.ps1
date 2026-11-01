# ============================================================
#  make-bonsai-icons.ps1
#
#  Builds four distinct .ico files for the desktop Bonsai
#  shortcuts, so they are no longer all the same picture.
#
#    Bonsai-Chat.ico   blue speech bubble  -> chat (starts everything)
#    Bonsai-API.ico    server rack         -> model/API server on 8010
#    Bonsai-WebUI.ico  browser window      -> Open WebUI on 9090 only
#    Bonsai-Stop.ico   red stop           -> stop the 8010 server
#
#  Icons are written as classic DIB (BMP) frames, not PNG-in-ICO,
#  because every Windows shell version renders DIB frames correctly.
#
#  Run:  pwsh -File make-bonsai-icons.ps1
# ============================================================

Add-Type -AssemblyName System.Drawing

$IconDir = 'C:\Users\Administrator\Desktop\launchers\icons'
$Sheet   = Join-Path $env:TEMP 'bonsai-icon-sheet.png'
$Sizes   = @(16, 24, 32, 48, 64, 128, 256)

# ---------------------------------------------------------------- drawings --
# Every drawing block gets ($g = Graphics, $s = size in px) and must paint a
# transparent-background, square image that stays readable at 16 px.

$DrawChat = {
    param($g, $s)
    $blue = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 37, 99, 235))

    # bubble body
    $x = $s * 0.08; $y = $s * 0.10; $w = $s * 0.84; $h = $s * 0.60
    $r = $s * 0.20; $d = 2 * $r
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $g.FillPath($blue, $path)

    # tail
    $tail = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $tailPts = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($s * 0.26, $y + $h - $s * 0.02),
        [System.Drawing.PointF]::new($s * 0.30, $s * 0.95),
        [System.Drawing.PointF]::new($s * 0.56, $y + $h - $s * 0.02)
    )
    $tail.AddPolygon($tailPts)
    $g.FillPath($blue, $tail)

    # three dots
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $dr = $s * 0.056
    $cy = $y + $h / 2
    foreach ($fx in 0.35, 0.50, 0.65) {
        $g.FillEllipse($white, $s * $fx - $dr, $cy - $dr, 2 * $dr, 2 * $dr)
    }

    $blue.Dispose(); $white.Dispose(); $path.Dispose(); $tail.Dispose()
}

$DrawApi = {
    param($g, $s)
    $slate = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 51, 65, 85))
    $green = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 34, 197, 94))

    $x = $s * 0.12; $w = $s * 0.76
    $bh = $s * 0.20; $gap = $s * 0.08
    $top = $s * 0.13
    for ($i = 0; $i -lt 3; $i++) {
        $y = $top + $i * ($bh + $gap)
        $g.FillRectangle($slate, $x, $y, $w, $bh)
        # status LED on the right of each unit
        $led = $s * 0.085
        $g.FillEllipse($green, $x + $w - $led - $s * 0.07, $y + $bh / 2 - $led / 2, $led, $led)
        # slot line on the left
        $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(200, 255, 255, 255))
        $g.FillRectangle($white, $x + $s * 0.07, $y + $bh / 2 - $s * 0.02, $w * 0.42, $s * 0.04)
        $white.Dispose()
    }
    $slate.Dispose(); $green.Dispose()
}

$DrawWeb = {
    param($g, $s)
    $frame = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 15, 118, 110))
    $paper = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $dot   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 15, 118, 110))
    $line  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 148, 163, 184))

    $x = $s * 0.07; $y = $s * 0.13; $w = $s * 0.86; $h = $s * 0.74
    $g.FillRectangle($frame, $x, $y, $w, $h)                      # title bar
    $g.FillRectangle($paper, $x, $y + $h * 0.26, $w, $h * 0.74)   # page

    # three window dots
    $dr = $s * 0.042
    foreach ($fx in 0.16, 0.26, 0.36) {
        $g.FillEllipse($dot, $x + $s * $fx, $y + $h * 0.13 - $dr, 2 * $dr, 2 * $dr)
    }
    # content lines
    $g.FillRectangle($line, $x + $w * 0.12, $y + $h * 0.45, $w * 0.76, $s * 0.055)
    $g.FillRectangle($line, $x + $w * 0.12, $y + $h * 0.63, $w * 0.52, $s * 0.055)

    $frame.Dispose(); $paper.Dispose(); $dot.Dispose(); $line.Dispose()
}

$DrawStop = {
    param($g, $s)
    $red   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 220, 38, 38))
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $g.FillEllipse($red, $s * 0.04, $s * 0.04, $s * 0.92, $s * 0.92)
    $q = $s * 0.34
    $g.FillRectangle($white, ($s - $q) / 2, ($s - $q) / 2, $q, $q)
    $red.Dispose(); $white.Dispose()
}

# ------------------------------------------------------------------ helpers --

function Get-IconBitmap {
    param([int]$Size, [scriptblock]$Draw)
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    & $Draw $g $Size
    $g.Dispose()
    return $bmp
}

# One classic DIB frame: BITMAPINFOHEADER + bottom-up BGRA + 1bpp AND mask.
function ConvertTo-DibFrame {
    param([System.Drawing.Bitmap]$Bitmap)
    $w = $Bitmap.Width; $h = $Bitmap.Height
    $andRow = [int]([math]::Floor(($w + 31) / 32) * 4)

    $ms = [System.IO.MemoryStream]::new()
    $bw = [System.IO.BinaryWriter]::new($ms)

    $bw.Write([int]40)                              # biSize
    $bw.Write([int]$w)                              # biWidth
    $bw.Write([int]($h * 2))                        # biHeight (XOR + AND)
    $bw.Write([int16]1)                             # biPlanes
    $bw.Write([int16]32)                            # biBitCount
    $bw.Write([int]0)                               # biCompression = BI_RGB
    $bw.Write([int]($w * $h * 4 + $andRow * $h))    # biSizeImage
    $bw.Write([int]0); $bw.Write([int]0)            # pels per meter
    $bw.Write([int]0); $bw.Write([int]0)            # clrUsed / clrImportant

    for ($y = $h - 1; $y -ge 0; $y--) {             # bottom-up
        for ($x = 0; $x -lt $w; $x++) {
            $c = $Bitmap.GetPixel($x, $y)
            $bw.Write([byte]$c.B); $bw.Write([byte]$c.G)
            $bw.Write([byte]$c.R); $bw.Write([byte]$c.A)
        }
    }
    $bw.Write([byte[]]::new($andRow * $h), 0, $andRow * $h)
    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    return $bytes
}

function Write-IcoFile {
    param([string]$Path, [scriptblock]$Draw, [int[]]$SizeList)
    $frames = @()
    foreach ($s in $SizeList) {
        $bmp = Get-IconBitmap -Size $s -Draw $Draw
        $frames += , (ConvertTo-DibFrame -Bitmap $bmp)
        $bmp.Dispose()
    }

    $fs = [System.IO.File]::Create($Path)
    $bw = [System.IO.BinaryWriter]::new($fs)
    $bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]$SizeList.Count)

    $offset = 6 + 16 * $SizeList.Count
    for ($i = 0; $i -lt $SizeList.Count; $i++) {
        $s = $SizeList[$i]
        $dim = [byte]0; if ($s -lt 256) { $dim = [byte]$s }
        $bw.Write($dim)                 # bWidth  (0 means 256)
        $bw.Write($dim)                 # bHeight
        $bw.Write([byte]0)              # bColorCount
        $bw.Write([byte]0)              # bReserved
        $bw.Write([int16]1)             # wPlanes
        $bw.Write([int16]32)            # wBitCount
        $bw.Write([int]$frames[$i].Length)
        $bw.Write([int]$offset)
        $offset += $frames[$i].Length
    }
    foreach ($f in $frames) { $bw.Write($f, 0, $f.Length) }
    $bw.Flush(); $bw.Dispose(); $fs.Dispose()
}

# --------------------------------------------------------------------- main --

$specs = @(
    @{ Name = 'Bonsai-Chat.ico';  Draw = $DrawChat; Label = 'chat / full stack' }
    @{ Name = 'Bonsai-API.ico';   Draw = $DrawApi;  Label = 'model server 8010' }
    @{ Name = 'Bonsai-WebUI.ico'; Draw = $DrawWeb;  Label = 'Open WebUI 9090' }
    @{ Name = 'Bonsai-Stop.ico';  Draw = $DrawStop; Label = 'stop 8010' }
)

New-Item -ItemType Directory -Path $IconDir -Force | Out-Null

foreach ($spec in $specs) {
    $out = Join-Path $IconDir $spec.Name
    Write-IcoFile -Path $out -Draw $spec.Draw -SizeList $Sizes

    # verify the container by parsing its own directory
    $raw = [System.IO.File]::ReadAllBytes($out)
    $frames = [BitConverter]::ToUInt16($raw, 4)
    $frameSizes = @()
    for ($i = 0; $i -lt $frames; $i++) {
        $w = $raw[6 + 16 * $i]
        if ($w -eq 0) { $w = 256 }
        $frameSizes += $w
    }
    $probe = [System.Drawing.Icon]::new($out, [System.Drawing.Size]::new(32, 32))
    Write-Host ("{0,-16} {1,7} bytes   frames={2} [{3}]  32px-load=OK" -f `
        $spec.Name, $raw.Length, $frames, ($frameSizes -join ','))
    $probe.Dispose()
}

# contact sheet: every icon at 64 px, plus its real 16 px frame blown up 5x
# with nearest-neighbour so small-size legibility is visible.
$cell = 96; $pad = 12
$sheetW = $specs.Count * $cell + ($specs.Count + 1) * $pad
$sheetH = 3 * $pad + 2 * $cell
$sbmp = [System.Drawing.Bitmap]::new($sheetW, $sheetH)
$sg = [System.Drawing.Graphics]::FromImage($sbmp)
$sg.Clear([System.Drawing.Color]::FromArgb(255, 245, 245, 245))
for ($i = 0; $i -lt $specs.Count; $i++) {
    $path = Join-Path $IconDir $specs[$i].Name
    $cx = $pad + $i * ($cell + $pad)

    $big = [System.Drawing.Icon]::new($path, [System.Drawing.Size]::new(64, 64))
    $sg.DrawIcon($big, [System.Drawing.Rectangle]::new($cx, $pad, $cell, $cell))
    $big.Dispose()

    $small = [System.Drawing.Icon]::new($path, [System.Drawing.Size]::new(16, 16))
    $sb = $small.ToBitmap()
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $sg.DrawImage($sb, [System.Drawing.Rectangle]::new($cx, 2 * $pad + $cell, $cell, $cell))
    $sb.Dispose(); $small.Dispose()
}
$sg.Dispose()
$sbmp.Save($Sheet, [System.Drawing.Imaging.ImageFormat]::Png)
$sbmp.Dispose()
Write-Host ""
Write-Host "contact sheet: $Sheet"
