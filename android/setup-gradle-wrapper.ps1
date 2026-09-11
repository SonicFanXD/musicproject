$tmpDir = Join-Path $env:TEMP 'gradle-wrapper-setup'
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

Write-Host '=== Descargando gradle-8.4-bin.zip ===' -ForegroundColor Cyan
Invoke-WebRequest -Uri 'https://services.gradle.org/distributions/gradle-8.4-bin.zip' -OutFile (Join-Path $tmpDir 'gradle.zip') -UseBasicParsing -TimeoutSec 300
Write-Host 'Descarga completada' -ForegroundColor Green

Write-Host '=== Extrayendo ===' -ForegroundColor Cyan
Expand-Archive -Path (Join-Path $tmpDir 'gradle.zip') -DestinationPath (Join-Path $tmpDir 'extracted') -Force
Write-Host 'Extracción completada' -ForegroundColor Green

Write-Host '=== Buscando gradle-wrapper.jar ===' -ForegroundColor Cyan
$jar = Get-ChildItem -Path (Join-Path $tmpDir 'extracted') -Recurse -Filter 'gradle-wrapper.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $jar) { Write-Host 'NO ENCONTRADO'; exit 1 }
Write-Host "Encontrado: $($jar.FullName)" -ForegroundColor Green
Write-Host "Tamaño: $($jar.Length) bytes" -ForegroundColor Green

Write-Host '=== Copiando a android/gradle/wrapper/ ===' -ForegroundColor Cyan
$DestDir = 'c:\Users\jonic\auroraplayer\android\gradle\wrapper'
if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }
Copy-Item -Path $jar.FullName -Destination (Join-Path $DestDir 'gradle-wrapper.jar') -Force
Write-Host 'Copia completada' -ForegroundColor Green

Write-Host '=== Limpiando ===' -ForegroundColor Cyan
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '=== Verificando ===' -ForegroundColor Cyan
if (Test-Path (Join-Path $DestDir 'gradle-wrapper.jar')) {
    $f = Get-Item (Join-Path $DestDir 'gradle-wrapper.jar')
    Write-Host "JAR OK: $($f.Name) - $($f.Length) bytes" -ForegroundColor Green
} else { Write-Host 'ERROR: JAR no existe' -ForegroundColor Red; exit 1 }
