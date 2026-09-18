param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not (Test-Path -LiteralPath $compiler)){throw '.NET Framework C# compiler not found. Build on 64-bit Windows with .NET Framework 4.8.'}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output=Join-Path $OutputDirectory 'AlienwareLightSwitch.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/win32manifest:$PSScriptRoot\src\app.manifest" "/win32icon:$PSScriptRoot\assets\app.ico" "/resource:$PSScriptRoot\assets\app.ico,app.ico" "/resource:$PSScriptRoot\src\AwccLighting.ps1,AwccLighting.ps1" "/out:$output" "$PSScriptRoot\src\LightSwitch.cs"
if($LASTEXITCODE -ne 0){throw 'Build failed.'}
Get-FileHash -LiteralPath $output -Algorithm SHA256
