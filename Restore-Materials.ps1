[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 can evaluate the parameter default before PSScriptRoot
# has its script value. Resolve the default in the script body instead.
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = $PSScriptRoot
}

function Resolve-MaterialPath {
    param([string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains(':') -or
        ($RelativePath -split '[/\\]' | Where-Object { $_ -eq '..' })) {
        throw "Invalid repository-relative material path: $RelativePath"
    }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $script:MaterialRoot $RelativePath))
    if (-not $fullPath.StartsWith($script:MaterialRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Material path leaves the repository: $RelativePath"
    }
    # Do not follow a junction/symlink when restoring repository materials.
    $currentPath = $fullPath
    while ($currentPath -and $currentPath.Length -gt $script:MaterialRoot.Length) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Material paths must not contain a junction or symlink: $RelativePath"
            }
        }
        $currentPath = [System.IO.Path]::GetDirectoryName($currentPath)
    }
    return $fullPath
}

function Assert-MaterialRecord {
    param($Record)
    if (-not $Record.PSObject.Properties['path'] -or
        -not $Record.PSObject.Properties['bytes'] -or
        -not $Record.PSObject.Properties['sha256']) {
        throw 'Each material record requires path, bytes, and sha256.'
    }
    if ([string]$Record.sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw "Invalid SHA-256 in materials.lock.json: $($Record.path)"
    }
    $recordLength = 0L
    if (-not [long]::TryParse([string]$Record.bytes, [ref]$recordLength) -or $recordLength -lt 0) {
        throw "Invalid byte count in materials.lock.json: $($Record.path)"
    }
    [void](Resolve-MaterialPath ([string]$Record.path))
}

function Test-MaterialFile {
    param([string]$Path, $Record)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        if ($stream.Length -ne [long]$Record.bytes) { return $false }
        $digest = [System.BitConverter]::ToString($hashAlgorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        return $digest -ceq [string]$Record.sha256
    }
    finally {
        $hashAlgorithm.Dispose()
        $stream.Dispose()
    }
}

$script:MaterialRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]'\/')
$script:MaterialRootPrefix = $script:MaterialRoot + [System.IO.Path]::DirectorySeparatorChar
$lockPath = Join-Path $script:MaterialRoot 'materials.lock.json'
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Missing materials.lock.json in $script:MaterialRoot. Use the complete repository."
}
$materialLock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $materialLock.PSObject.Properties['schemaVersion'] -or $materialLock.schemaVersion -ne 1 -or
    -not $materialLock.PSObject.Properties['files'] -or @($materialLock.files).Count -eq 0) {
    throw 'Unsupported or empty materials.lock.json; expected schemaVersion 1 and a non-empty files array.'
}

$paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($record in $materialLock.files) {
    Assert-MaterialRecord $record
    $recordPath = Resolve-MaterialPath ([string]$record.path)
    if (-not $paths.Add($recordPath)) { throw "Duplicate material path: $($record.path)" }
    if ($record.PSObject.Properties['parts']) {
        foreach ($part in $record.parts) { Assert-MaterialRecord $part }
    }
}

$verified = 0
$restored = 0
foreach ($record in $materialLock.files) {
    $destination = Resolve-MaterialPath ([string]$record.path)
    if (Test-MaterialFile $destination $record) {
        Write-Host "[verified] $($record.path)"
        $verified++
        continue
    }
    if (-not $record.PSObject.Properties['parts'] -or @($record.parts).Count -eq 0) {
        throw "Missing or damaged material: $($record.path). Restore this file from a fresh copy of this complete repository. No runtime downloads are performed."
    }
    $partBytes = 0L
    foreach ($part in $record.parts) {
        $partPath = Resolve-MaterialPath ([string]$part.path)
        if (-not (Test-MaterialFile $partPath $part)) {
            throw "Missing or damaged material chunk: $($part.path). Restore this chunk from a fresh copy of this repository."
        }
        $partBytes += [long]$part.bytes
    }
    if ($partBytes -ne [long]$record.bytes) {
        throw "Chunk lengths do not match the complete material: $($record.path)"
    }
    $destinationDirectory = [System.IO.Path]::GetDirectoryName($destination)
    [void][System.IO.Directory]::CreateDirectory($destinationDirectory)
    $temporaryPath = $destination + '.restore-' + [guid]::NewGuid().ToString('N') + '.tmp'
    Write-Host "[restoring] $($record.path) from $(@($record.parts).Count) local chunks"
    try {
        $outputStream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            foreach ($part in $record.parts) {
                $inputStream = [System.IO.File]::OpenRead((Resolve-MaterialPath ([string]$part.path)))
                try { $inputStream.CopyTo($outputStream, 1048576) }
                finally { $inputStream.Dispose() }
            }
            $outputStream.Flush($true)
        }
        finally { $outputStream.Dispose() }
        if (-not (Test-MaterialFile $temporaryPath $record)) {
            throw "Reassembled material failed SHA-256 verification: $($record.path)"
        }
        if ([System.IO.File]::Exists($destination)) {
            # PowerShell 5.1 coerces $null to an empty string for this overload.
            # NullString passes the actual null backup path required by .NET.
            [System.IO.File]::Replace($temporaryPath, $destination, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $destination)
        }
        $restored++
        Write-Host "[restored] $($record.path)"
    }
    finally {
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
    }
}
Write-Host "Materials ready: $verified verified, $restored restored. All material hashes match materials.lock.json."
