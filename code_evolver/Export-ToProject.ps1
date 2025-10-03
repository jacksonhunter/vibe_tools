# Export-ToProject.ps1
# Copies minimal code-evolver files to another project

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

Write-Host "Exporting Code Evolver to project..." -ForegroundColor Cyan
Write-Host "  Target: $TargetProject" -ForegroundColor Gray

# Create tools directory in target project
$targetToolPath = Join-Path $TargetProject $ToolFolder "code-evolver"
if (!(Test-Path $targetToolPath)) {
    New-Item -ItemType Directory -Path $targetToolPath -Force | Out-Null
}

# Copy essential files only
$essentials = @(
    "Track-CodeEvolution.ps1",
    "lib",
    "grammars",
    "templates"
)

foreach ($item in $essentials) {
    $source = Join-Path $PSScriptRoot $item
    $dest = Join-Path $targetToolPath $item

    if (Test-Path $source -PathType Container) {
        Write-Host "  Copying $item directory..."
        Copy-Item -Path $source -Destination $dest -Recurse -Force
    } else {
        Write-Host "  Copying $item..."
        Copy-Item -Path $source -Destination $dest -Force
    }
}

# Create simple runner script
$runnerScript = @'
# run.ps1 - Code Evolver Runner
param([Parameter(ValueFromRemainingArguments)]$args)

$scriptPath = Join-Path $PSScriptRoot "Track-CodeEvolution.ps1"
& $scriptPath @args
'@

$runnerPath = Join-Path $targetToolPath "run.ps1"
Set-Content -Path $runnerPath -Value $runnerScript

# Add to .gitignore if requested
if ($CreateGitIgnore) {
    $gitignorePath = Join-Path $TargetProject ".gitignore"
    $ignoreEntries = @(
        "",
        "# Code Evolution Analysis",
        "code-evolution-analysis/",
        ""
    )

    if (Test-Path $gitignorePath) {
        $content = Get-Content $gitignorePath -Raw
        if ($content -notlike "*code-evolution-analysis/*") {
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
Write-Host "  .\$ToolFolder\code-evolver\run.ps1 -ClassName MyClass -ExportHtml" -ForegroundColor White
Write-Host "`nOr create an alias in the project:"
Write-Host "  Set-Alias track '.\$ToolFolder\code-evolver\run.ps1'" -ForegroundColor Gray