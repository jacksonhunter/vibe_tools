# Install-GlobalTool.ps1
# Installs code-referencer as a globally accessible command

param(
    [string]$InstallPath = "$env:LOCALAPPDATA\VibeTools",
    [switch]$LocalOnly,  # Only copy files, don't add to PATH
    [switch]$SkipAlias   # Don't create PowerShell alias
)

$ErrorActionPreference = 'Stop'

if ($LocalOnly) {
    Write-Host "Installing Code Referencer (local copy only)..." -ForegroundColor Cyan
    Write-Host "  Note: You'll need to use the full path to run it" -ForegroundColor Yellow
} else {
    Write-Host "Installing Code Referencer globally (adding to PATH)..." -ForegroundColor Cyan
}

# 1. Create installation directory
$toolPath = Join-Path $InstallPath "code-referencer"
if (!(Test-Path $toolPath)) {
    New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
}

# 2. Copy all necessary files
$sourceFiles = @{
    "Find-CodeReferences.ps1" = "find-references.ps1"  # Rename for cleaner command
    "lib" = "lib"
    "grammars" = "grammars"
    "package.json" = "package.json"
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
    }
}

# 3. Install npm dependencies
Write-Host "  Installing dependencies..."
Push-Location $toolPath
try {
    & npm install --production 2>&1 | Out-Null
} finally {
    Pop-Location
}

# 4. Create batch wrapper for Windows
$batchWrapper = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0find-references.ps1" %*
"@
$batchPath = Join-Path $toolPath "find-references.cmd"
Set-Content -Path $batchPath -Value $batchWrapper -Encoding ASCII

# 5. Create PowerShell module wrapper
$moduleContent = @'
function Invoke-FindReferences {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $PSScriptRoot "find-references.ps1"
    & $scriptPath @Arguments
}

Set-Alias -Name find-references -Value Invoke-FindReferences
Export-ModuleMember -Function Invoke-FindReferences -Alias find-references
'@

$modulePath = Join-Path $toolPath "FindReferences.psm1"
Set-Content -Path $modulePath -Value $moduleContent

# 6. Add to PATH (unless -LocalOnly specified)
if (-not $LocalOnly) {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$toolPath*") {
        Write-Host "  Adding to user PATH..."
        [Environment]::SetEnvironmentVariable(
            "Path",
            "$currentPath;$toolPath",
            "User"
        )
        Write-Host "  PATH updated. Restart your terminal to use 'find-references' command." -ForegroundColor Yellow
    }
}

# 7. Create PowerShell profile alias (unless -SkipAlias specified)
if (-not $SkipAlias -and -not $LocalOnly) {
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (!(Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $aliasCommand = "Set-Alias -Name find-references -Value '$toolPath\find-references.ps1'"
    $profileContent = Get-Content $profilePath -ErrorAction SilentlyContinue

    if ($profileContent -notcontains $aliasCommand) {
        Write-Host "  Adding alias to PowerShell profile..."
        Add-Content -Path $profilePath -Value "`n# Code Referencer Tool"
        Add-Content -Path $profilePath -Value $aliasCommand
    }
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "`nUsage:" -ForegroundColor Cyan

if ($LocalOnly) {
    Write-Host "  Local installation only. Use full path to run:"
    Write-Host "    & '$toolPath\find-references.ps1' -FilePath script.js" -ForegroundColor White
} else {
    Write-Host "  From any directory (after terminal restart):"
    Write-Host "    find-references -FilePath script.js -ProjectPath ." -ForegroundColor White

    if (-not $SkipAlias) {
        Write-Host "`n  From PowerShell (immediately after reload):"
        Write-Host "    find-references -FilePath script.py" -ForegroundColor Gray
    }

    Write-Host "`n  Note: Restart your terminal or run this to use immediately:" -ForegroundColor Yellow
    Write-Host "    `$env:Path += ';$toolPath'" -ForegroundColor Gray
}