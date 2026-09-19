[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$Offline,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
$exitCode = 0

function Get-JavaMajor {
    param([string]$JavaHome)
    $java = Join-Path $JavaHome 'bin\java.exe'
    if (-not (Test-Path -LiteralPath $java -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin\javac.exe') -PathType Leaf)) { return 0 }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $java
    $startInfo.Arguments = '-version'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            return 0
        }
        $versionText = $stdoutTask.Result + $stderrTask.Result
        if ($process.ExitCode -ne 0) { return 0 }
        if ($versionText -match '(?i)(?:openjdk|java)\s+(?:version\s+)?"?(\d+)(?:\.(\d+))?') {
            $major = [int]$Matches[1]
            if ($major -eq 1) { return [int]$Matches[2] }
            return $major
        }
        return 0
    }
    catch { return 0 }
    finally { $process.Dispose() }
}

function Find-Jdk {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($env:JAVA_HOME) { $candidates.Add($env:JAVA_HOME.Trim('"')) }
    foreach ($jdkRoot in @('D:\AllTools\Java', (Join-Path $env:ProgramFiles 'Java'),
        (Join-Path $env:ProgramFiles 'Eclipse Adoptium'), (Join-Path $env:ProgramFiles 'Microsoft'))) {
        if (Test-Path -LiteralPath $jdkRoot -PathType Container) {
            foreach ($directory in (Get-ChildItem -LiteralPath $jdkRoot -Directory | Sort-Object Name -Descending)) {
                $candidates.Add($directory.FullName)
            }
        }
    }
    $candidates.Add((Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'))
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jbr'))
    }
    $javaCommand = Get-Command java.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($javaCommand) {
        $candidates.Add([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName($javaCommand.Source)))
    }
    $fallback = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $major = Get-JavaMajor $candidate
        if ($major -eq 21) { return [pscustomobject]@{ Path = $candidate; Major = $major } }
        # Gradle 8.11.1 supports running on Java up to version 23.
        if ($major -ge 17 -and $major -le 23 -and $null -eq $fallback) {
            $fallback = [pscustomobject]@{ Path = $candidate; Major = $major }
        }
    }
    if ($fallback) { return $fallback }
    throw 'No compatible JDK was found. Install JDK 21 (recommended; JDK 17-23 supported), then set JAVA_HOME to its installation folder.'
}

function ConvertFrom-JavaProperty {
    param([string]$Value)
    $builder = New-Object System.Text.StringBuilder
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        if ($character -eq '\' -and $index + 1 -lt $Value.Length) {
            $index++
            $character = $Value[$index]
            if ($character -eq 'u' -and $index + 4 -lt $Value.Length -and
                $Value.Substring($index + 1, 4) -match '^[0-9a-fA-F]{4}$') {
                [void]$builder.Append([char][Convert]::ToInt32($Value.Substring($index + 1, 4), 16))
                $index += 4
                continue
            }
            switch ($character) {
                't' { $character = [char]9 }
                'n' { $character = [char]10 }
                'r' { $character = [char]13 }
                'f' { $character = [char]12 }
            }
        }
        [void]$builder.Append($character)
    }
    return $builder.ToString()
}

function Find-AndroidSdk {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $localPropertiesPath = Join-Path $repositoryRoot 'local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf) {
        $propertiesText = [System.IO.File]::ReadAllText($localPropertiesPath)
        $sdkMatches = [regex]::Matches($propertiesText, '(?m)^\s*sdk\.dir\s*[:=]\s*([^\r\n]*)')
        if ($sdkMatches.Count -gt 0) {
            $candidates.Add((ConvertFrom-JavaProperty $sdkMatches[$sdkMatches.Count - 1].Groups[1].Value))
        }
    }
    if ($env:ANDROID_HOME) { $candidates.Add($env:ANDROID_HOME.Trim('"')) }
    if ($env:ANDROID_SDK_ROOT) { $candidates.Add($env:ANDROID_SDK_ROOT.Trim('"')) }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk')) }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not [System.IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $repositoryRoot $candidate }
        if ((Test-Path -LiteralPath $candidate -PathType Container) -and
            ((Test-Path -LiteralPath (Join-Path $candidate 'platforms') -PathType Container) -or
             (Test-Path -LiteralPath (Join-Path $candidate 'cmdline-tools') -PathType Container))) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Android SDK not found. Install Android Studio/SDK with Android API 36 and SDK Build-Tools, then set ANDROID_HOME or sdk.dir in local.properties.'
}

function Set-LocalSdkProperty {
    param([string]$SdkPath)
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $SdkPath.Replace('\', '/').ToCharArray()) {
        if ([int]$character -gt 126 -or [int]$character -lt 32) {
            [void]$builder.Append(('\u{0:x4}' -f [int]$character))
        }
        else { [void]$builder.Append($character) }
    }
    $sdkLine = 'sdk.dir=' + $builder.ToString()
    $path = Join-Path $repositoryRoot 'local.properties'
    $text = ''
    if (Test-Path -LiteralPath $path -PathType Leaf) { $text = [System.IO.File]::ReadAllText($path) }
    $pattern = '(?m)^[ \t]*sdk\.dir[ \t]*[:=][^\r\n]*'
    if ([regex]::IsMatch($text, $pattern)) {
        # MatchEvaluator keeps backslashes and dollar signs in a local path literal.
        $text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $sdkLine })
    }
    else {
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }
        $text += $sdkLine + "`r`n"
    }
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-OfflineGradleCache {
    # The wrapper runs before Gradle's --offline flag takes effect. Check its
    # exact URL-derived cache directory so it cannot need an initial download.
    Add-Type -AssemblyName System.Numerics
    $propertiesPath = Join-Path $repositoryRoot 'gradle\wrapper\gradle-wrapper.properties'
    $propertiesText = [System.IO.File]::ReadAllText($propertiesPath)
    $urlMatch = [regex]::Match($propertiesText, '(?m)^distributionUrl=(.*)\r?$')
    if (-not $urlMatch.Success) { throw 'Cannot locate distributionUrl in Gradle wrapper properties.' }
    $distributionUrl = ConvertFrom-JavaProperty $urlMatch.Groups[1].Value.TrimEnd([char]13)
    $distributionName = [System.IO.Path]::GetFileNameWithoutExtension(([uri]$distributionUrl).AbsolutePath)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($distributionUrl)) }
    finally { $md5.Dispose() }
    [array]::Reverse($bytes)
    $positiveBytes = New-Object byte[] ($bytes.Length + 1)
    [array]::Copy($bytes, $positiveBytes, $bytes.Length)
    $number = New-Object System.Numerics.BigInteger (,$positiveBytes)
    $alphabet = '0123456789abcdefghijklmnopqrstuvwxyz'
    $cacheId = ''
    do {
        $remainder = [int]($number % 36)
        $cacheId = $alphabet[$remainder] + $cacheId
        $number = [System.Numerics.BigInteger]::Divide($number, 36)
    } while ($number -gt 0)
    $gradleUserHome = $env:GRADLE_USER_HOME
    if (-not $gradleUserHome) { $gradleUserHome = Join-Path $env:USERPROFILE '.gradle' }
    $cachePath = Join-Path $gradleUserHome ("wrapper\dists\{0}\{1}" -f $distributionName, $cacheId)
    $readyMarker = Join-Path $cachePath ($distributionName + '.zip.ok')
    $gradleDirectoryName = $distributionName -replace '-(?:bin|all)$', ''
    $cachedGradle = Join-Path $cachePath ($gradleDirectoryName + '\bin\gradle.bat')
    if (-not (Test-Path -LiteralPath $readyMarker -PathType Leaf) -or
        -not (Test-Path -LiteralPath $cachedGradle -PathType Leaf)) {
        throw "Offline build requires a cached Gradle wrapper distribution. Run Build.ps1 once with network access first. Expected cache: $cachePath"
    }
}

function Assert-ApkMaterials {
    param([string]$ApkPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $lock = Get-Content -LiteralPath (Join-Path $repositoryRoot 'materials.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($record in $lock.files) {
        $relativePath = ([string]$record.path).Replace('\', '/')
        if ($relativePath -match '^runtime/android-assets/(runtime|dsh)/') {
            $assetPath = 'assets/' + $relativePath.Substring('runtime/android-assets/'.Length)
            if ($expected.ContainsKey($assetPath)) { throw "Duplicate APK material in lock file: $assetPath" }
            $expected[$assetPath] = $record
        }
    }
    if ($expected.Count -eq 0) { throw 'No runtime/dsh APK materials are recorded in materials.lock.json.' }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
    try {
        $actual = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '^assets/(runtime|dsh)/' -and -not $entry.FullName.EndsWith('/')) {
                if ($actual.ContainsKey($entry.FullName)) { throw "Duplicate APK asset: $($entry.FullName)" }
                if (-not $expected.ContainsKey($entry.FullName)) { throw "APK contains an unlocked runtime/dsh asset: $($entry.FullName)" }
                $actual[$entry.FullName] = $entry
            }
        }
        foreach ($assetPath in ($expected.Keys | Sort-Object)) {
            if (-not $actual.ContainsKey($assetPath)) { throw "APK is missing a required material: $assetPath" }
            $record = $expected[$assetPath]
            $entry = $actual[$assetPath]
            if ($entry.Length -ne [long]$record.bytes) { throw "APK material length mismatch: $assetPath" }
            $stream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $digest = [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ($digest -cne [string]$record.sha256) { throw "APK material SHA-256 mismatch: $assetPath" }
            Write-Host "[APK verified] $assetPath"
        }
    }
    finally { $archive.Dispose() }
    Write-Host "Verified all $($expected.Count) runtime/dsh APK assets against materials.lock.json."
}

try {
    & (Join-Path $repositoryRoot 'Restore-Materials.ps1') -RepositoryRoot $repositoryRoot
    if ($VerifyOnly) {
        Write-Host 'Verification complete. Gradle was not run and no device was contacted.'
    }
    else {
        $jdk = Find-Jdk
        $sdk = Find-AndroidSdk
        $env:JAVA_HOME = $jdk.Path
        $env:ANDROID_HOME = $sdk
        $env:ANDROID_SDK_ROOT = $sdk
        Set-LocalSdkProperty $sdk
        Write-Host "JDK $($jdk.Major): $($jdk.Path)"
        Write-Host "Android SDK: $sdk"
        if ($Offline) { Assert-OfflineGradleCache }
        if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'keystore.properties') -PathType Leaf) {
            Write-Host 'Signing: using the local keystore.properties configuration.'
        }
        else {
            Write-Host 'Signing: the upstream release configuration uses your local debug key when no release key is configured.'
        }
        $gradleArguments = @(':app:assembleRelease', '--console=plain')
        if ($Offline) { $gradleArguments += '--offline' }
        Push-Location $repositoryRoot
        try {
            & (Join-Path $repositoryRoot 'gradlew.bat') @gradleArguments
            if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE." }
        }
        finally { Pop-Location }
        $apkPath = Join-Path $repositoryRoot 'app\build\outputs\apk\release\app-release.apk'
        if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
            throw "Gradle completed but the signed release APK was not found: $apkPath"
        }
        Assert-ApkMaterials $apkPath
        $distDirectory = Join-Path $repositoryRoot 'dist'
        [void][System.IO.Directory]::CreateDirectory($distDirectory)
        $deliveryPath = Join-Path $distDirectory 'DSHBox-v1.3.1-local.apk'
        Copy-Item -LiteralPath $apkPath -Destination $deliveryPath -Force
        $deliveryHash = (Get-FileHash -LiteralPath $deliveryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host ''
        Write-Host "SUCCESS: $deliveryPath" -ForegroundColor Green
        Write-Host "APK SHA-256: $deliveryHash"
        Write-Host 'Runtime/DSH materials match the locked upstream materials. Your APK has a local signature and is not byte-identical to the upstream APK.'
    }
}
catch {
    $exitCode = 1
    Write-Host ''
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
}
finally {
    if (-not $NoPause) { [void](Read-Host 'Press Enter to close') }
}
exit $exitCode
