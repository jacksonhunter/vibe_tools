 #!/usr/bin/env pwsh
<#
.SYNOPSIS
    Find all references to symbols defined in a file across the codebase

.DESCRIPTION
    Analyzes a source file to extract all defined symbols (classes, functions, methods, globals)
    then searches for references to those symbols in all same-language files in the project.
    Uses tree-sitter AST parsing for accurate symbol detection and reference matching.

.PARAMETER FilePath
    Path to the file to analyze for symbol definitions

.PARAMETER ProjectPath
    Root directory to search for references (default: current directory)

.PARAMETER IncludeGlobals
    Include global variable definitions in analysis

.PARAMETER IncludeExports
    Include module exports in analysis

.PARAMETER IncludeConstants
    Include constant definitions in analysis

.PARAMETER OutputFormat
    Output format: text, json, or html (default: text)

.PARAMETER ExportHtml
    Generate an interactive HTML report

.PARAMETER ExportJson
    Export results to JSON file

.PARAMETER Verbose
    Show detailed progress during analysis

.EXAMPLE
    # Find all references to symbols in UserService.js
    ./Find-CodeReferences.ps1 -FilePath src/UserService.js

.EXAMPLE
    # Generate HTML report for a Python file
    ./Find-CodeReferences.ps1 -FilePath lib/database.py -ExportHtml

.EXAMPLE
    # Search specific directory with JSON output
    ./Find-CodeReferences.ps1 -FilePath utils.js -ProjectPath ./src -OutputFormat json
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [string]$ProjectPath = ".",

    [switch]$IncludeGlobals,

    [switch]$IncludeExports,

    [switch]$IncludeConstants,

    [string]$OutputFormat = "text",

    [switch]$ExportHtml,

    [switch]$ExportJson,

    [string]$OutputDir = "./code-reference-analysis"
)

# Ensure absolute paths
$FilePath = Resolve-Path $FilePath -ErrorAction Stop
$ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parserPath = Join-Path -Path $scriptDir -ChildPath "lib\reference-parser.js"

if (-not (Test-Path $parserPath)) {
    Write-Error "Parser not found at: $parserPath"
    exit 1
}

# Detect language from file extension
function Get-Language {
    param([string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLower()

    $languageMap = @{
        '.js' = 'javascript'
        '.jsx' = 'javascript'
        '.mjs' = 'javascript'
        '.cjs' = 'javascript'
        '.ts' = 'javascript'
        '.tsx' = 'javascript'
        '.py' = 'python'
        '.ps1' = 'powershell'
        '.psm1' = 'powershell'
        '.psd1' = 'powershell'
        '.sh' = 'bash'
        '.bash' = 'bash'
        '.r' = 'r'
        '.cs' = 'csharp'
        '.csx' = 'csharp'
    }

    # Handle case-insensitive R extension
    if ($ext -eq '.R') {
        return 'r'
    }

    return $languageMap[$ext]
}

# Extract symbols from target file
function Get-FileSymbols {
    param(
        [string]$Path,
        [bool]$IncludeGlobals,
        [bool]$IncludeExports,
        [bool]$IncludeConstants
    )

    Write-Verbose "Extracting symbols from: $Path"

    # Build filter arguments
    $filterArgs = @()
    if (-not $IncludeGlobals) { $filterArgs += "--exclude-globals" }
    if (-not $IncludeExports) { $filterArgs += "--exclude-exports" }
    if (-not $IncludeConstants) { $filterArgs += "--exclude-constants" }

    # Use temp file for complex arguments
    $tempFile = [System.IO.Path]::GetTempFileName()
    $argData = @{
        mode = "extract"
        file = $Path
        filters = $filterArgs
    } | ConvertTo-Json -Compress

    # Write without BOM for Node.js compatibility
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tempFile, $argData, $utf8NoBom)

    try {
        # Redirect stderr to null to avoid debug output
        $output = & node $parserPath "@$tempFile" 2>$null
        if (!$output) {
            throw "No output from parser"
        }
        $result = $output | ConvertFrom-Json

        if ($result.error) {
            throw "Parser error: $($result.error)"
        }

        return $result.symbols
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# Search for references in a file
function Find-SymbolReferences {
    param(
        [string]$Path,
        [array]$Symbols
    )

    Write-Verbose "Searching for references in: $Path"

    # Prepare symbol data for parser
    $tempFile = [System.IO.Path]::GetTempFileName()
    $argData = @{
        mode = "references"
        file = $Path
        symbols = $Symbols
    } | ConvertTo-Json -Compress -Depth 10

    # Write without BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tempFile, $argData, $utf8NoBom)

    try {
        # Redirect stderr to null to avoid debug output
        $output = & node $parserPath "@$tempFile" 2>$null
        if (!$output) {
            throw "No output from parser"
        }
        $result = $output | ConvertFrom-Json

        if ($result.error) {
            Write-Warning "Error searching $Path : $($result.error)"
            return @()
        }

        return $result.references
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# Main analysis
Write-Host "`nAnalyzing symbols in: $FilePath" -ForegroundColor Cyan
Write-Host "Searching project: $ProjectPath`n" -ForegroundColor Gray

# Get target file language
$targetLanguage = Get-Language -Path $FilePath
if (-not $targetLanguage) {
    Write-Error "Unsupported file type: $FilePath"
    exit 1
}

Write-Verbose "Detected language: $targetLanguage"

# Extract symbols from target file
$symbols = Get-FileSymbols -Path $FilePath `
    -IncludeGlobals $IncludeGlobals `
    -IncludeExports $IncludeExports `
    -IncludeConstants $IncludeConstants

if ($symbols.Count -eq 0) {
    Write-Host "No symbols found in target file" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($symbols.Count) symbols to analyze:" -ForegroundColor Green
$symbols | ForEach-Object {
    Write-Host "  [$($_.type)] $($_.name)" -ForegroundColor DarkGray
}
Write-Host ""

# Find all same-language files in project (including the source file itself)
$searchPattern = "*" + [System.IO.Path]::GetExtension($FilePath)
$projectFiles = Get-ChildItem -Path $ProjectPath -Filter $searchPattern -Recurse -File

Write-Host "Searching $($projectFiles.Count) $targetLanguage files for references...`n" -ForegroundColor Cyan

# Initialize results
$referenceMap = @{}
foreach ($symbol in $symbols) {
    $referenceMap[$symbol.name] = @{
        type = $symbol.type
        definition = @{
            file = $FilePath
            line = $symbol.line
            endLine = $symbol.endLine
        }
        references = @()
        totalCount = 0
    }
}

# Search each file for references
$fileCount = 0
foreach ($file in $projectFiles) {
    $fileCount++
    if ($Verbose) {
        Write-Progress -Activity "Searching for references" `
            -Status "$fileCount/$($projectFiles.Count): $($file.Name)" `
            -PercentComplete (($fileCount / $projectFiles.Count) * 100)
    }

    $refs = Find-SymbolReferences -Path $file.FullName -Symbols $symbols

    foreach ($ref in $refs) {
        if ($referenceMap.ContainsKey($ref.symbol)) {
            $referenceMap[$ref.symbol].references += @{
                file = $file.FullName
                line = $ref.line
                context = $ref.context
                usage = $ref.usage
            }
            $referenceMap[$ref.symbol].totalCount++
        }
    }
}

if ($Verbose) {
    Write-Progress -Activity "Searching for references" -Completed
}

# Sort symbols by reference count
$sortedSymbols = $referenceMap.GetEnumerator() |
    Sort-Object { -$_.Value.totalCount }, Name

# Output results based on format
switch ($OutputFormat.ToLower()) {
    "json" {
        $jsonOutput = $sortedSymbols | ForEach-Object {
            @{
                name = $_.Key
                type = $_.Value.type
                definition = $_.Value.definition
                totalReferences = $_.Value.totalCount
                references = $_.Value.references
            }
        } | ConvertTo-Json -Depth 10

        if ($ExportJson) {
            if (-not (Test-Path $OutputDir)) {
                New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
            }
            $jsonPath = Join-Path $OutputDir "reference-analysis.json"
            $jsonOutput | Out-File -FilePath $jsonPath -Encoding UTF8
            Write-Host "`nJSON report saved to: $jsonPath" -ForegroundColor Green
        } else {
            Write-Output $jsonOutput
        }
    }

    "html" {
        # HTML output will be implemented with template
        Write-Host "HTML output coming soon..." -ForegroundColor Yellow
    }

    default {
        # Text output
        Write-Host "=" * 60 -ForegroundColor DarkCyan
        Write-Host "Symbol Reference Analysis" -ForegroundColor Cyan
        Write-Host "=" * 60 -ForegroundColor DarkCyan
        Write-Host ""

        foreach ($symbol in $sortedSymbols) {
            $name = $symbol.Key
            $data = $symbol.Value

            # Symbol header
            $headerColor = if ($data.totalCount -gt 10) { "Green" }
                          elseif ($data.totalCount -gt 5) { "Yellow" }
                          elseif ($data.totalCount -gt 0) { "White" }
                          else { "DarkGray" }

            Write-Host "$($data.type.ToUpper()): $name" -ForegroundColor $headerColor
            Write-Host "  References: $($data.totalCount)" -ForegroundColor Gray

            if ($data.totalCount -gt 0) {
                # Group references by file
                $fileGroups = $data.references | Group-Object { $_.file }

                foreach ($group in $fileGroups) {
                    # GetRelativePath is not available in older PowerShell versions
                    $relativePath = if ($group.Name.StartsWith($ProjectPath)) {
                        $group.Name.Substring($ProjectPath.Length).TrimStart('\', '/')
                    } else {
                        $group.Name
                    }

                    # Mark internal references
                    $isInternal = $group.Name -eq $FilePath
                    $fileLabel = if ($isInternal) { "$relativePath (internal)" } else { $relativePath }
                    $fileColor = if ($isInternal) { "Cyan" } else { "DarkCyan" }

                    Write-Host "  $fileLabel" -ForegroundColor $fileColor

                    foreach ($ref in $group.Group) {
                        $contextInfo = if ($ref.context) { " (in $($ref.context))" } else { "" }
                        Write-Host "    Line $($ref.line): $($ref.usage)$contextInfo" -ForegroundColor DarkGray
                    }
                }
            } else {
                Write-Host "  (No references found)" -ForegroundColor DarkGray
            }

            Write-Host ""
        }

        # Summary
        Write-Host "=" * 60 -ForegroundColor DarkCyan
        $totalRefs = ($sortedSymbols | ForEach-Object { $_.Value.totalCount } | Measure-Object -Sum).Sum
        $unusedSymbols = @($sortedSymbols | Where-Object { $_.Value.totalCount -eq 0 })

        Write-Host "Summary:" -ForegroundColor Cyan
        Write-Host "  Total symbols: $($symbols.Count)" -ForegroundColor Gray
        Write-Host "  Total references: $totalRefs" -ForegroundColor Gray
        Write-Host "  Unused symbols: $($unusedSymbols.Count)" -ForegroundColor $(if ($unusedSymbols.Count -gt 0) { "Yellow" } else { "Gray" })

        if ($unusedSymbols.Count -gt 0) {
            Write-Host "`n  Unused:" -ForegroundColor Yellow
            foreach ($unused in $unusedSymbols) {
                Write-Host "    - [$($unused.Value.type)] $($unused.Key)" -ForegroundColor DarkYellow
            }
        }
    }
}

if ($ExportHtml) {
    Write-Host "`nGenerating HTML report..." -ForegroundColor Cyan
    # TODO: Implement HTML generation
    Write-Host "HTML generation will be implemented next" -ForegroundColor Yellow
}

Write-Host "`nAnalysis complete!" -ForegroundColor Green