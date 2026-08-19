@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo Downloading pvideo manifest and binaries...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$scriptDir = $env:SCRIPT_DIR;" ^
  "$manifestUrl = if ($env:PVIDEO_MANIFEST) { $env:PVIDEO_MANIFEST } else { 'https://pizazz.s3.bitiful.net/pvideo.json' };" ^
  "$outputRoot = if ($env:PVIDEO_OUTPUT_ROOT) { $env:PVIDEO_OUTPUT_ROOT } elseif (Test-Path (Join-Path $scriptDir 'app\src\main')) { Join-Path $scriptDir 'app\src\main' } else { $scriptDir };" ^
  "$assetsDir = Join-Path $outputRoot 'assets\pvideo';" ^
  "$jniDir = Join-Path $outputRoot 'jniLibs';" ^
  "New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null;" ^
  "$headers = @{ 'User-Agent' = 'okhttp/4.12.0' };" ^
  "$manifestPath = Join-Path $assetsDir 'pvideo.json';" ^
  "Invoke-WebRequest -Uri $manifestUrl -Headers $headers -OutFile $manifestPath;" ^
  "$manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json;" ^
  "$installed = 0;" ^
  "foreach ($property in $manifest.PSObject.Properties) {" ^
  "  $name = $property.Name;" ^
  "  if ($name.EndsWith('.md5') -or -not $name.StartsWith('pvideo-')) { continue }" ^
  "  $url = [string]$property.Value;" ^
  "  if ([string]::IsNullOrWhiteSpace($url)) { continue }" ^
  "  $abi = $name.Substring(7);" ^
  "  if (@('arm64-v8a','armeabi-v7a','x86','x86_64') -notcontains $abi) { throw 'unsupported pvideo ABI entry: ' + $name }" ^
  "  $uri = [Uri]$url;" ^
  "  $suffix = [IO.Path]::GetExtension($uri.AbsolutePath);" ^
  "  if ([string]::IsNullOrWhiteSpace($suffix)) { $suffix = '.zip' }" ^
  "  $archivePath = Join-Path $assetsDir ($name + $suffix);" ^
  "  Invoke-WebRequest -Uri $url -Headers $headers -OutFile $archivePath;" ^
  "  $extractDir = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString());" ^
  "  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null;" ^
  "  Expand-Archive -Force -Path $archivePath -DestinationPath $extractDir;" ^
  "  $binary = Get-ChildItem -Path $extractDir -Recurse -File | Where-Object { $_.Name -eq $name } | Select-Object -First 1;" ^
  "  if (-not $binary) { $binary = Get-ChildItem -Path $extractDir -Recurse -File | Select-Object -First 1 }" ^
  "  if (-not $binary) { throw $archivePath + ' contains no files' }" ^
  "  $actualMd5 = (Get-FileHash -Algorithm MD5 $binary.FullName).Hash.ToLowerInvariant();" ^
  "  $expectedProperty = $manifest.PSObject.Properties[$name + '.md5'];" ^
  "  if ($expectedProperty -and $actualMd5 -ne ([string]$expectedProperty.Value).ToLowerInvariant()) { throw $name + ' md5 mismatch: ' + $actualMd5 + ' != ' + $expectedProperty.Value }" ^
  "  $soDir = Join-Path $jniDir $abi;" ^
  "  New-Item -ItemType Directory -Force -Path $soDir | Out-Null;" ^
  "  $soPath = Join-Path $soDir 'libpvideo.so';" ^
  "  Copy-Item -Force $binary.FullName $soPath;" ^
  "  Remove-Item -Recurse -Force $extractDir;" ^
  "  Write-Host ($name + ': ' + $archivePath + ' -> ' + $soPath + ' md5=' + $actualMd5);" ^
  "  $installed += 1;" ^
  "}" ^
  "Write-Host ('manifest: ' + $manifestPath);" ^
  "if ($installed -eq 0) { throw 'manifest contained no pvideo-* entries' }"

if %ERRORLEVEL% NEQ 0 goto failed

echo.
echo Done.
pause
exit /b 0

:failed
echo.
echo Download failed.
pause
exit /b 1
