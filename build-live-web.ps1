$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$outputsRoot = Split-Path -Parent $projectRoot
$workspaceRoot = Split-Path -Parent $outputsRoot
$dateRoot = Split-Path -Parent $workspaceRoot
$toolRoot = Join-Path $dateRoot 'we\work\pixora-build'
$flutterRoot = Join-Path $toolRoot 'flutter\flutter'
$publishableKey = $env:INDETAIL_SUPABASE_PUBLISHABLE_KEY

if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  $publishableKey = Read-Host 'Paste the Supabase publishable key (sb_publishable_...)'
}
if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  throw 'A Supabase publishable key is required to build the live website.'
}

$supabaseUrl = 'https://hulfgxqbdliaxulqjunj.supabase.co'
$cachedDart = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$flutterSnapshot = Join-Path $flutterRoot 'bin\cache\flutter_tools.snapshot'

Push-Location $projectRoot
try {
  $buildStartedAt = Get-Date
  if (Test-Path -LiteralPath $flutterSnapshot) {
    $env:APPDATA = Join-Path $projectRoot 'work\tool-appdata'
    $env:ANDROID_USER_HOME = Join-Path $projectRoot 'work\android-user'
    $env:ANDROID_SDK_ROOT = Join-Path $toolRoot 'android-sdk'
    $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
    $env:JAVA_HOME = Join-Path $toolRoot 'jdk\jdk-17.0.21.0.2+1'
    $env:GRADLE_USER_HOME = Join-Path (Split-Path -Parent $dateRoot) '_tools\gradle-cache'
    $env:PUB_CACHE = Join-Path $toolRoot 'flutter-appdata\Pub\Cache'
    $env:FLUTTER_ROOT = $flutterRoot
    $env:PATH = (Join-Path $flutterRoot 'bin') + ';' + $env:PATH
    $env:DART_SUPPRESS_ANALYTICS = 'true'
    $env:CI = 'true'
    & $cachedDart $flutterSnapshot build web --release --no-pub --base-href '/' `
      "--dart-define=SUPABASE_URL=$supabaseUrl" `
      "--dart-define=SUPABASE_ANON_KEY=$publishableKey"
  } else {
    $flutterCommand = Get-Command flutter -ErrorAction Stop
    & $flutterCommand.Source build web --release --no-pub --base-href '/' `
      "--dart-define=SUPABASE_URL=$supabaseUrl" `
      "--dart-define=SUPABASE_ANON_KEY=$publishableKey"
  }

  $flutterExitCode = $LASTEXITCODE
  $bundlePath = Join-Path $projectRoot 'build\web\main.dart.js'
  if ($flutterExitCode -ne 0) {
    if (-not (Test-Path -LiteralPath $bundlePath)) {
      throw "Flutter web build failed with exit code $flutterExitCode."
    }
    $existingBundle = Get-Content -LiteralPath $bundlePath -Raw
    $requiredRpcNames = @('admin_attendance_report', 'admin_import_paid_holidays', 'my_attendance_summary', 'paid_leave_balance', 'saturday_full_day_credit')
    if (-not $existingBundle.Contains($supabaseUrl) -or -not $existingBundle.Contains($publishableKey) -or @($requiredRpcNames | Where-Object { -not $existingBundle.Contains($_) }).Count -gt 0) {
      throw "Flutter web build failed with exit code $flutterExitCode and the existing bundle is not the current live INDETAIL build."
    }
    Write-Warning 'Flutter exited abnormally; the existing live web bundle already contains the current project and attendance features, so it will be prepared for publishing.'
  }

  $indexPath = Join-Path $projectRoot 'build\web\index.html'
  $bootstrapPath = Join-Path $projectRoot 'build\web\flutter_bootstrap.js'
  $versionInfo = Get-Content -LiteralPath (Join-Path $projectRoot 'build\web\version.json') -Raw | ConvertFrom-Json
  $assetVersion = "$($versionInfo.version)-$($versionInfo.build_number)"
  $index = Get-Content -LiteralPath $indexPath -Raw
  $index = [regex]::Replace($index, '<base href="[^"]*">', '<base href="/">')
  $index = $index.Replace('src="flutter_bootstrap.js"', "src=`"flutter_bootstrap.js?v=$assetVersion`"")
  [System.IO.File]::WriteAllText($indexPath, $index, [System.Text.UTF8Encoding]::new($false))

  $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
  $bootstrap = $bootstrap.Replace('main.dart.js', "main.dart.js?v=$assetVersion")
  [System.IO.File]::WriteAllText($bootstrapPath, $bootstrap, [System.Text.UTF8Encoding]::new($false))

  $bundle = Get-Content -LiteralPath (Join-Path $projectRoot 'build\web\main.dart.js') -Raw
  if ($index -notmatch '<base href="/">') {
    throw 'The website must use the root path when hosted on Hatchable.'
  }
  if (-not $bundle.Contains($supabaseUrl) -or -not $bundle.Contains($publishableKey)) {
    throw 'The web bundle is missing the live Supabase URL or publishable key.'
  }

  Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build\web') -Recurse -File |
    Measure-Object -Property Length -Sum | Select-Object Count, Sum
} finally {
  Pop-Location
}
