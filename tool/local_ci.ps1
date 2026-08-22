[CmdletBinding()]
param(
    [switch] $SkipInterfaces
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$flutterw = Join-Path $PSScriptRoot 'flutterw.ps1'
Push-Location $repoRoot
try {
    # On Windows the "python" command may be the Microsoft Store stub, which does
    # not actually provide an interpreter. Resolve a real Python from
    # PURE_LIVE_PYTHON, PATH, common install locations or the Codex runtime.
    function Resolve-PureLivePython {
        param([string]$Explicit)
        $candidates = @(
            $Explicit,
            'python',
            (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
            (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
        ) | Where-Object { $_ }
        foreach ($c in $candidates) {
            $exe = $null
            if (Test-Path -LiteralPath $c -PathType Leaf) {
                $exe = $c
            } elseif ($c -eq 'python') {
                # Verify the PATH entry is a real interpreter, not the Store stub.
                $cmd = Get-Command python -ErrorAction SilentlyContinue
                if ($cmd -and $cmd.Source) { $exe = $cmd.Source }
            } else {
                $found = Get-ChildItem -LiteralPath $c -Filter 'python.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($found) { $exe = $found.FullName }
            }
            if (-not $exe) { continue }
            try {
                $version = & $exe --version 2>&1
                if ($LASTEXITCODE -eq 0 -and ($version -join ' ') -match '\d+\.\d+') {
                    Write-Host "Using Python: $exe"
                    return $exe
                }
            } catch {
                # Unusable candidate (Store stub or no permission); try the next one.
            }
        }
        throw 'No usable Python interpreter found. Install Python or point PURE_LIVE_PYTHON at python.exe.'
    }

    & $flutterw pub get --enforce-lockfile
    if ($LASTEXITCODE) { exit $LASTEXITCODE }

    $python = Resolve-PureLivePython -Explicit $env:PURE_LIVE_PYTHON

    & $python (Join-Path $PSScriptRoot 'audit_built_in_kotlin.py')
    if ($LASTEXITCODE) { exit $LASTEXITCODE }

    # This file vendors a large JavaScript implementation in raw Dart strings;
    # dart format rewrites the embedded source and makes upstream comparison noisy.
    $formatExclusions = @('lib/core/scripts/douyin_sign.dart')
    # Keep the result strongly typed as an array. When exactly one Dart file
    # changed, PowerShell otherwise unwraps it to a scalar and argument
    # splatting passes each character to `dart format` as a separate path.
    [string[]] $dartFiles = @(
        git diff --name-only --diff-filter=ACMR HEAD -- '*.dart'
        git ls-files --others --exclude-standard -- '*.dart'
    ) | Where-Object {
        $_ -and
        $_ -notin $formatExclusions -and
        -not $_.StartsWith('plugins/built_in_kotlin/', [StringComparison]::OrdinalIgnoreCase) -and
        -not $_.StartsWith('plugins/flv_lzc/', [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $_)
    } | Sort-Object -Unique
    if ($dartFiles.Count -gt 0) {
        & $flutterw dart format --output=none --set-exit-if-changed @dartFiles
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
    }

    & $flutterw analyze --no-fatal-infos --no-fatal-warnings
    if ($LASTEXITCODE) { exit $LASTEXITCODE }

    & $flutterw test
    if ($LASTEXITCODE) { exit $LASTEXITCODE }

    if (-not $SkipInterfaces) {
        & $python (Join-Path $PSScriptRoot 'interface_probe.py')
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
    }
} finally {
    Pop-Location
}