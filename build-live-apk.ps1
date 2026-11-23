$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$outputsRoot = Split-Path -Parent $projectRoot
$workspaceRoot = Split-Path -Parent $outputsRoot
$dateRoot = Split-Path -Parent $workspaceRoot
$toolRoot = Join-Path $dateRoot 'we\work\pixora-build'
$flutterRoot = $null
$flutter = $null

$flutterFromCache = Join-Path $toolRoot 'flutter\flutter\bin\flutter.bat'
if (Test-Path -LiteralPath $flutterFromCache) {
  $flutterRoot = Join-Path $toolRoot 'flutter\flutter'
  $flutter = $flutterFromCache
  $env:APPDATA = Join-Path $workspaceRoot 'work\tool-appdata'
  $env:ANDROID_USER_HOME = Join-Path $workspaceRoot 'work\android-user'
  $env:ANDROID_SDK_ROOT = Join-Path $toolRoot 'android-sdk'
  $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
  $env:JAVA_HOME = Join-Path $toolRoot 'jdk\jdk-17.0.21.0.2+1'
  $env:GRADLE_USER_HOME = Join-Path (Split-Path -Parent $dateRoot) '_tools\gradle-cache'
  $env:PUB_CACHE = Join-Path $toolRoot 'flutter-appdata\Pub\Cache'
  $env:FLUTTER_ROOT = $flutterRoot
  $env:PATH = (Join-Path $flutterRoot 'bin') + ';' + $env:PATH
  $env:DART_SUPPRESS_ANALYTICS = 'true'
  $env:CI = 'true'
} else {
  $flutterCommand = Get-Command flutter -ErrorAction Stop
  $flutter = $flutterCommand.Source
  $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutter)
}

$dart = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$flutterSnapshot = Join-Path $flutterRoot 'bin\cache\flutter_tools.snapshot'
$supabaseUrl = 'https://hulfgxqbdliaxulqjunj.supabase.co'
$publishableKey = $env:INDETAIL_SUPABASE_PUBLISHABLE_KEY
if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  $publishableKey = Read-Host 'Paste the Supabase publishable key (sb_publishable_...)'
}
if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  throw 'A Supabase publishable key is required to build the live APK.'
}

$builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'
$liveApk = Join-Path $outputsRoot 'INDETAIL-live-debug.apk'
$directApk = Join-Path $outputsRoot 'INDETAIL.apk'
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(?<name>\d+\.\d+\.\d+)\+(?<number>\d+)\s*$')
if (-not $versionMatch.Success) {
  throw 'Could not read the app version and build number from pubspec.yaml.'
}
$buildName = $versionMatch.Groups['name'].Value
$buildNumber = $versionMatch.Groups['number'].Value
$versionedApk = Join-Path $outputsRoot "INDETAIL-v$buildName-build$buildNumber.apk"
$normalBuildSucceeded = $false

Push-Location $projectRoot
try {
  & $flutter build apk --debug --no-pub --build-name $buildName --build-number $buildNumber `
    "--dart-define=SUPABASE_URL=$supabaseUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$publishableKey"
  $normalBuildSucceeded = ($LASTEXITCODE -eq 0)

  if (-not $normalBuildSucceeded) {
    Write-Warning 'The Flutter wrapper exited abnormally. Compiling the debug kernel directly and packaging it with Gradle.'

    $intermediate = Join-Path $projectRoot 'build\app\intermediates\flutter\debug'
    $dill = Join-Path $intermediate 'app.dill'
    $kernel = Join-Path $intermediate 'flutter_assets\kernel_blob.bin'
    $depfile = Join-Path $intermediate 'kernel_snapshot_program.d'
    $runtime = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dartaotruntime.exe'
    $frontend = Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64\frontend_server_aot.dart.snapshot'
    $sdkRoot = (Join-Path $flutterRoot 'bin\cache\artifacts\engine\common\flutter_patched_sdk').Replace('\', '/') + '/'
    New-Item -ItemType Directory -Force -Path $intermediate, (Split-Path -Parent $kernel) | Out-Null

    $compilerArguments = @(
      $frontend
      '--sdk-root'; $sdkRoot
      '--target=flutter'
      '--no-print-incremental-dependencies'
      "-DSUPABASE_URL=$supabaseUrl"
      "-DSUPABASE_ANON_KEY=$publishableKey"
      '-Ddart.vm.profile=false'
      '-Ddart.vm.product=false'
      '--enable-asserts'
      '--track-creation-locations'
      '--no-link-platform'
      '--packages'; (Join-Path $projectRoot '.dart_tool\package_config.json')
      '--output-dill'; $dill
      '--depfile'; $depfile
      '--incremental'
      '--initialize-from-dill'; $dill
      '--verbosity=error'
      'package:indetail/main.dart'
    )
    & $runtime @compilerArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dill)) {
      throw 'Flutter kernel compilation failed. Run flutter pub get, then inspect the compiler output above.'
    }
    Copy-Item -LiteralPath $dill -Destination $kernel -Force
    $kernelText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($kernel))
    if (-not $kernelText.Contains($supabaseUrl) -or -not $kernelText.Contains($publishableKey)) {
      throw 'The compiled debug kernel does not contain the live Supabase URL and publishable key.'
    }

    Push-Location (Join-Path $projectRoot 'android')
    try {
      & .\gradlew.bat :app:assembleDebug --no-daemon -x :app:compileFlutterBuildDebug
      if ($LASTEXITCODE -ne 0) {
        throw "Gradle APK packaging failed with exit code $LASTEXITCODE."
      }
    } finally {
      Pop-Location
    }
  }

  if (-not (Test-Path -LiteralPath $builtApk)) {
    throw 'The Android build completed without producing app-debug.apk.'
  }
  Copy-Item -LiteralPath $builtApk -Destination $liveApk -Force
  Copy-Item -LiteralPath $builtApk -Destination $directApk -Force
  Copy-Item -LiteralPath $builtApk -Destination $versionedApk -Force
  Get-Item -LiteralPath $liveApk | Select-Object FullName, Length, LastWriteTime
  Get-Item -LiteralPath $directApk | Select-Object FullName, Length, LastWriteTime
  Get-Item -LiteralPath $versionedApk | Select-Object FullName, Length, LastWriteTime
} finally {
  Pop-Location
}
