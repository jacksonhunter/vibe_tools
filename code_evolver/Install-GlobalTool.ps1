# Install-GlobalTool.ps1
# Installs code-evolver as a globally accessible command

param(
    [string]$InstallPath = "$env:LOCALAPPDATA\VibeTools",
    [switch]$LocalOnly,  # Only copy files, don't add to PATH
    [switch]$SkipAlias   # Don't create PowerShell alias
)

$ErrorActionPreference = 'Stop'

if ($LocalOnly) {
    Write-Host "Installing Code Evolver (local copy only)..." -ForegroundColor Cyan
    Write-Host "  Note: You'll need to use the full path to run it" -ForegroundColor Yellow
} else {
    Write-Host "Installing Code Evolver globally (adding to PATH)..." -ForegroundColor Cyan
}

# 1. Create installation directory
$toolPath = Join-Path $InstallPath "code-evolver"
if (!(Test-Path $toolPath)) {
    New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
}

# 2. Copy all necessary files
$sourceFiles = @{
    "Track-CodeEvolution.ps1" = "code-evolver.ps1"  # Rename for cleaner command
    "lib" = "lib"
    "grammars" = "grammars"
    "templates" = "templates"
}

foreach ($source in $sourceFiles.Keys) {
    $sourcePath = Join-Path $PSScriptRoot $source
    $destName = $sourceFiles[$source]
    $destPath = Join-Path $toolPath $destName

    if (Test-Path $sourcePath -PathType Container) {
        Write-Host "  Copying $source directory..."
        Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
    } elseif (Test-Path $sourcePath) {
        Write-Host "  Copying $source..."
        Copy-Item -Path $sourcePath -Destination $destPath -Force
    } else {
        Write-Host "  Skipping $source (not found)" -ForegroundColor Yellow
    }
}

# 3. Create batch wrapper for Windows
$batchWrapper = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0code-evolver.ps1" %*
"@
$batchPath = Join-Path $toolPath "code-evolver.cmd"
Set-Content -Path $batchPath -Value $batchWrapper -Encoding ASCII

# 4. Create PowerShell module wrapper
$moduleContent = @'
function Invoke-CodeEvolver {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $PSScriptRoot "code-evolver.ps1"
    & $scriptPath @Arguments
}

Set-Alias -Name code-evolver -Value Invoke-CodeEvolver
Export-ModuleMember -Function Invoke-CodeEvolver -Alias code-evolver
'@

$modulePath = Join-Path $toolPath "CodeEvolver.psm1"
Set-Content -Path $modulePath -Value $moduleContent

# 5. Add to PATH (unless -LocalOnly specified)
if (-not $LocalOnly) {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$toolPath*") {
        Write-Host "  Adding to user PATH..."
        [Environment]::SetEnvironmentVariable(
            "Path",
            "$currentPath;$toolPath",
            "User"
        )
        Write-Host "  PATH updated. Restart your terminal to use 'code-evolver' command." -ForegroundColor Yellow
    }
}

# 6. Create PowerShell profile alias (unless -SkipAlias specified)
if (-not $SkipAlias -and -not $LocalOnly) {
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (!(Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $aliasCommand = "Set-Alias -Name code-evolver -Value '$toolPath\code-evolver.ps1'"
    $profileContent = Get-Content $profilePath -ErrorAction SilentlyContinue

    if ($profileContent -notcontains $aliasCommand) {
        Write-Host "  Adding alias to PowerShell profile..."
        Add-Content -Path $profilePath -Value "`n# Code Evolver Tool"
        Add-Content -Path $profilePath -Value $aliasCommand
    }
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "`nUsage:" -ForegroundColor Cyan

if ($LocalOnly) {
    Write-Host "  Local installation only. Use full path to run:"
    Write-Host "    & '$toolPath\code-evolver.ps1' -ClassName MyClass" -ForegroundColor White
} else {
    Write-Host "  From any directory (after terminal restart):"
    Write-Host "    code-evolver -ClassName MyClass" -ForegroundColor White

    if (-not $SkipAlias) {
        Write-Host "`n  From PowerShell (immediately after reload):"
        Write-Host "    code-evolver -ClassName MyClass" -ForegroundColor Gray
    }

    Write-Host "`n  Note: Restart your terminal or run this to use immediately:" -ForegroundColor Yellow
    Write-Host "    `$env:Path += ';$toolPath'" -ForegroundColor Gray
}