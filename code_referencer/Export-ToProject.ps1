# Export-ToProject.ps1
# Copies minimal code-referencer files to another project

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetProject,

    [string]$ToolFolder = ".tools",
    [switch]$CreateGitIgnore
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path $TargetProject)) {
    throw "Target project path does not exist: $TargetProject"
}

Write-Host "Exporting Code Referencer to project..." -ForegroundColor Cyan
Write-Host "  Target: $TargetProject" -ForegroundColor Gray

# Create tools directory in target project
$targetToolPath = Join-Path $TargetProject $ToolFolder "code-referencer"
if (!(Test-Path $targetToolPath)) {
    New-Item -ItemType Directory -Path $targetToolPath -Force | Out-Null
}

# Copy essential files only
$essentials = @(
    "Find-CodeReferences.ps1",
    "lib",
    "grammars",
    "package.json"
)

foreach ($item in $essentials) {
    $source = Join-Path $PSScriptRoot $item
    $dest = Join-Path $targetToolPath $item

    if (Test-Path $source -PathType Container) {
        Write-Host "  Copying $item directory..."
        Copy-Item -Path $source -Destination $dest -Recurse -Force
    } elseif (Test-Path $source) {
        Write-Host "  Copying $item..."
        Copy-Item -Path $source -Destination $dest -Force
    }
}

# Install npm dependencies
Write-Host "  Installing dependencies..."
Push-Location $targetToolPath
try {
    & npm install --production 2>&1 | Out-Null
} finally {
    Pop-Location
}

# Create simple runner script
$runnerScript = @'
# run.ps1 - Code Referencer Runner
param([Parameter(ValueFromRemainingArguments)]$args)

$scriptPath = Join-Path $PSScriptRoot "Find-CodeReferences.ps1"
& $scriptPath @args
'@

$runnerPath = Join-Path $targetToolPath "run.ps1"
Set-Content -Path $runnerPath -Value $runnerScript

# Add to .gitignore if requested
if ($CreateGitIgnore) {
    $gitignorePath = Join-Path $TargetProject ".gitignore"
    $ignoreEntries = @(
        "",
        "# Code Reference Analysis",
        "code-reference-analysis/",
        ""
    )

    if (Test-Path $gitignorePath) {
        $content = Get-Content $gitignorePath -Raw
        if ($content -notlike "*code-reference-analysis/*") {
            Add-Content -Path $gitignorePath -Value ($ignoreEntries -join "`n")
            Write-Host "  Added to .gitignore"
        }
    } else {
        Set-Content -Path $gitignorePath -Value ($ignoreEntries -join "`n")
        Write-Host "  Created .gitignore"
    }
}

Write-Host "`nExport complete!" -ForegroundColor Green
Write-Host "`nUsage from project root:" -ForegroundColor Cyan
Write-Host "  .\$ToolFolder\code-referencer\run.ps1 -FilePath MyClass.cs -ProjectPath ." -ForegroundColor White
Write-Host "`nOr create an alias in the project:"
Write-Host "  Set-Alias find-refs '.\$ToolFolder\code-referencer\run.ps1'" -ForegroundColor Gray