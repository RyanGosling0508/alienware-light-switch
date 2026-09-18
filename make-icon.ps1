param([string]$Output=(Join-Path $PSScriptRoot 'assets\app.ico'))
Add-Type -AssemblyName System.Drawing
$bitmap=New-Object Drawing.Bitmap(256,256)
$g=[Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([Drawing.Color]::FromArgb(14,18,27))
$ring=New-Object Drawing.Pen([Drawing.Color]::FromArgb(91,224,196),18)
$ring.StartCap=$ring.EndCap=[Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($ring,57,62,142,142,-50,280)
$g.DrawLine($ring,128,43,128,122)
$icon=[Drawing.Icon]::FromHandle($bitmap.GetHicon())
$file=[IO.File]::Create($Output)
try{$icon.Save($file)}finally{$file.Dispose();$icon.Dispose();$ring.Dispose();$g.Dispose();$bitmap.Dispose()}
