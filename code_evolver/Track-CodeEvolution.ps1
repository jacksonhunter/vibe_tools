#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Track code evolution using your existing Acorn-based parsing logic

.DESCRIPTION
    This script combines PowerShell Git integration with your exact Acorn-based
    JavaScript parser for accurate code segment extraction and evolution tracking.

.PARAMETER BaseClass
    Name of the base class to track inheritance from

.PARAMETER ClassName
    Specific class name to track

.PARAMETER FilePath
    Specific file to analyze (optional)

.PARAMETER OutputDir
    Directory to store analysis results (default: ./code-evolution-analysis)

.PARAMETER ShowDiffs
    Display evolution diffs in console

.PARAMETER ExportHtml
    Export results to HTML report

.PARAMETER ExportUnifiedDiff
    Export results to unified diff text format for analysis

.PARAMETER ExportCompressedDiff
    Export compressed diff showing all changes inline with final version

.PARAMETER Parser
    Parser file to use for code analysis (default: javascript-parser.js)
    Must be a .js file in the lib/parsers/ directory

.PARAMETER Verbose
    Show detailed progress messages during execution

.EXAMPLE
    .\Track-CodeEvolution.ps1 -BaseClass "BaseService" -ShowDiffs

.EXAMPLE
    .\Track-CodeEvolution.ps1 -ClassName "UserService" -FilePath "src/UserService.js" -ExportHtml

.EXAMPLE
    .\Track-CodeEvolution.ps1 -ClassName "MyClass" -ExportUnifiedDiff -ExportCompressedDiff

.EXAMPLE
    .\Track-CodeEvolution.ps1 -ClassName "MyClass" -Parser "tree-sitter-parser.js" -FilePath "src/my_class.py"
#>

param(
    [string]$BaseClass,
    [string]$ClassName,
    [string]$FunctionName,
    [switch]$Globals,
    [switch]$Exports,
    [string]$FilePath,
    [string]$OutputDir = "./code-evolution-analysis",
    [string]$ConfigDir = "./config",
    [string]$Parser = "javascript-parser.js",  # Parser file to use
    [switch]$ShowDiffs,
    [switch]$ExportHtml,
    [switch]$ExportUnifiedDiff,
    [switch]$ExportCompressedDiff,
    [switch]$Verbose
)

function Test-Prerequisites {
    # Check if we're in a Git repository
    if (-not (Test-Path ".git")) {
        Write-Error "Not in a Git repository. Please run from repository root."
        return $false
    }
    
    # Check if Node.js is available
    try {
        $nodeVersion = node --version 2>$null
        Write-Verbose "Node.js version: $nodeVersion"
    }
    catch {
        Write-Error "Node.js is required but not found in PATH."
        Write-Host "Please install Node.js from https://nodejs.org/"
        return $false
    }
    
    # Check if the specified parser exists
    $parserPath = Join-Path $PSScriptRoot "lib\parsers\$Parser"
    if (-not (Test-Path $parserPath)) {
        Write-Error "Parser '$Parser' not found in lib/parsers/ directory."
        # List available parsers
        $availableParsers = Get-ChildItem (Join-Path $PSScriptRoot "lib\parsers") -Filter "*.js" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($availableParsers) {
            Write-Host "Available parsers: $($availableParsers -join ', ')" -ForegroundColor Yellow
        }
        return $false
    }

    Write-Verbose "Using parser: $Parser"
    
    # Check if Acorn dependencies are installed
    $packagePath = Join-Path $PSScriptRoot "package.json"
    if (-not (Test-Path $packagePath)) {
        Write-Host "Setting up Node.js dependencies..." -ForegroundColor Yellow
        Setup-NodeDependencies
    }
    
    return $true
}

function Setup-NodeDependencies {
    $packageJson = @{
        name = "code-evolution-tracker"
        version = "1.0.0"
        description = "Node.js dependencies for code evolution tracking"
        dependencies = @{
            acorn = "^8.11.2"
            "acorn-walk" = "^8.3.0"
        }
    }
    
    $packageJson | ConvertTo-Json | Set-Content "package.json"
    
    Write-Host "Installing Acorn dependencies..." -ForegroundColor Yellow
    npm install
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install Node.js dependencies. Please run 'npm install acorn acorn-walk' manually."
        exit 1
    }
    
    Write-Host "Dependencies installed successfully." -ForegroundColor Green
}

function Build-ExtractionContext {
    param(
        [hashtable]$Parameters,
        [hashtable]$Config
    )
    
    $context = @{
        Elements = @()
        Filters = @{}
        Exclusions = @()
        IncludeGuards = $false
        IncludeIIFE = $false
        PreserveContext = $false
        Visibility = $null
    }
    
    # Handle each parameter - they can combine
    if ($Parameters.BaseClass) {
        $context.Elements += "class"
        $context.Filters.Extends = $Parameters.BaseClass
    }
    
    if ($Parameters.ClassName) {
        $context.Elements += "class"
        $context.Filters.ClassName = $Parameters.ClassName
    }
    
    if ($Parameters.FunctionName) {
        # Include both functions AND methods, preserving class context
        $context.Elements += @("function", "method", "arrow")
        $context.Filters.FunctionName = $Parameters.FunctionName
        $context.PreserveContext = $true
    }
    
    if ($Parameters.Globals) {
        $context.Elements += "global"
        $context.IncludeGuards = $true
        $context.IncludeIIFE = $true
    }
    
    if ($Parameters.Exports) {
        $context.Elements += "export"
        $context.Visibility = "public"
    }
    
    # Special handling for FilePath-only mode
    if ($Parameters.FilePath -and 
        -not ($Parameters.BaseClass -or $Parameters.ClassName -or 
              $Parameters.FunctionName -or $Parameters.Globals -or $Parameters.Exports)) {
        # FilePath only - extract meaningful elements without duplication
        $context.Elements = @("class", "function", "constant")
        $context.Exclusions = @("method", "arrow")  # Avoid duplication from classes
        $context.ScopeFilter = "top-level"
    }
    
    # No parameters at all - warn and extract everything
    if (-not $Parameters.FilePath -and 
        -not ($Parameters.BaseClass -or $Parameters.ClassName -or 
              $Parameters.FunctionName -or $Parameters.Globals -or $Parameters.Exports)) {
        Write-Warning "No filters specified - extracting all top-level elements from all files"
        $context.Elements = @("class", "function", "constant")
        $context.ScopeFilter = "top-level"
    }
    
    # FilePath always acts as a scope limiter when present
    if ($Parameters.FilePath) {
        $context.ScopeToFile = $Parameters.FilePath
    }
    
    # Remove duplicates from elements array
    $context.Elements = $context.Elements | Select-Object -Unique
    
    return $context
}

function Get-LanguageConfiguration {
    param(
        [string]$ConfigDir,
        [string]$FilePath,
        [string]$Parser = $null
    )
    
    # Load configuration files
    $languageConfigPath = Join-Path $ConfigDir "languages.json"
    $rulesConfigPath = Join-Path $ConfigDir "extraction-rules.json"
    
    # Use default configs if not found
    if (-not (Test-Path $languageConfigPath)) {
        Write-Verbose "Language config not found at $languageConfigPath, using defaults"
        return Get-DefaultLanguageConfig
    }
    
    if (-not (Test-Path $rulesConfigPath)) {
        Write-Verbose "Extraction rules not found at $rulesConfigPath, using defaults"
        return Get-DefaultExtractionRules
    }
    
    $languageConfig = Get-Content $languageConfigPath | ConvertFrom-Json
    $extractionRules = Get-Content $rulesConfigPath | ConvertFrom-Json
    
    # Detect language from file extension if parser not specified
    if (-not $Parser -and $FilePath) {
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $detectedLanguage = $null
    
    foreach ($lang in $languageConfig.languages.PSObject.Properties) {
        if ($lang.Value.extensions -contains $extension) {
            $detectedLanguage = $lang.Name
            Write-Verbose "Detected language: $detectedLanguage for file $FilePath"
                
                # Select appropriate parser based on language
                switch ($lang.Value.parser) {
                    "acorn" { $Parser = "javascript-parser.js" }
                    "tree-sitter-javascript" { $Parser = "tree-sitter-parser.js" }
                    "tree-sitter-python" { $Parser = "python-parser.js" }
                    "tree-sitter-powershell" { $Parser = "powershell-parser.js" }
                    "tree-sitter-bash" { $Parser = "bash-parser.js" }
                    "tree-sitter-r" { $Parser = "r-parser.js" }
                    default { $Parser = "javascript-parser.js" }
                }
            break
        }
    }
    
    if (-not $detectedLanguage) {
        # Default to JavaScript if unknown
        $detectedLanguage = "javascript"
            $Parser = "javascript-parser.js"
        Write-Verbose "Unknown extension $extension, defaulting to JavaScript"
    }
    } else {
        # Try to detect language from parser name
        $detectedLanguage = switch -Regex ($Parser) {
            "javascript|acorn" { "javascript" }
            "python" { "python" }
            "powershell" { "powershell" }
            "bash|sh" { "bash" }
            "r-parser" { "r" }
            default { "javascript" }
        }
    }
    
    return @{
        Language = $detectedLanguage
        Parser = $Parser
        LanguageConfig = $languageConfig.languages.$detectedLanguage
        ExtractionRules = $extractionRules.extractionRules
    }
}

function Get-DefaultLanguageConfig {
    # Minimal default configuration for backward compatibility
    return @{
        Language = "javascript"
        LanguageConfig = @{
            extensions = @(".js", ".jsx")
            parser = "acorn"
            elements = @{
                class = @{ patterns = @("class_declaration") }
                function = @{ patterns = @("function_declaration") }
                method = @{ patterns = @("method_definition") }
                constant = @{ patterns = @("const_declaration") }
            }
        }
        ExtractionRules = @{
            BaseClass = @{ requires = @("class"); filter = "extends" }
            ClassName = @{ requires = @("class"); filter = "name" }
            FilePath = @{ requires = @("class", "function", "constant") }
        }
    }
}

function Get-GitFileVersions {
    param(
        [string]$BaseClass,
        [string]$ClassName,
        [string]$FunctionName,
        [bool]$Globals,
        [bool]$Exports,
        [string]$FilePath,
        [string]$OutputDir
    )
    
    $results = @()
    
    # Build search patterns for Git
    $searchPatterns = @()
    
    if ($BaseClass) {
        $searchPatterns += "extends.*$BaseClass"
        $searchPatterns += "extends $BaseClass"
    }
    
    if ($ClassName) {
        $searchPatterns += "class $ClassName"
        $searchPatterns += "class.*$ClassName"
    }
    
    if ($FunctionName) {
        # Search for function declarations and method definitions
        $searchPatterns += "function $FunctionName"
        $searchPatterns += "$FunctionName\s*[:=]\s*function"
        $searchPatterns += "$FunctionName\s*[:=]\s*\([^)]*\)\s*=>"
        $searchPatterns += "^\s*$FunctionName\s*\([^)]*\)\s*\{"
    }
    
    if ($Globals) {
        # Search for global assignments and window/global properties
        $searchPatterns += "window\."
        $searchPatterns += "global\."
        $searchPatterns += "globalThis\."
        $searchPatterns += "^\s*var\s+"
        $searchPatterns += "if\s*\(!window\."
    }
    
    if ($Exports) {
        # Search for export statements
        $searchPatterns += "export\s+"
        $searchPatterns += "module\.exports"
        $searchPatterns += "exports\."
    }
    
    # Find relevant files
    if ($FilePath) {
        $relevantFiles = @($FilePath)
    }
    else {
        $relevantFiles = @()
        foreach ($pattern in $searchPatterns) {
            Write-Verbose "Searching for pattern: $pattern"
            
            # Get files that ever contained the pattern
            $files = git log --all -G $pattern --name-only --pretty=format: | 
                Where-Object { $_ -match "\.(js|jsx|ts|tsx)$" } |
                Sort-Object -Unique
            
            $relevantFiles += $files
        }
        $relevantFiles = $relevantFiles | Where-Object { $_ } | Sort-Object -Unique
    }
    
    if (-not $relevantFiles) {
        Write-Warning "No relevant files found"
        return @()
    }
    
    Write-Host "Found $($relevantFiles.Count) relevant files" -ForegroundColor Green
    
    # For each file, get all versions
    foreach ($file in $relevantFiles) {
        Write-Verbose "Processing file: $file"
        
        # Get commit history for this file
        $commits = git log --follow --pretty=format:"%H|%ai|%s|%an" -- $file
        
        if (-not $commits) { continue }
        
        foreach ($commitLine in $commits) {
            if ([string]::IsNullOrWhiteSpace($commitLine)) { continue }
            
            $parts = $commitLine -split '\|', 4
            if ($parts.Count -lt 4) { continue }
            
            $commit = $parts[0]
            $date = $parts[1]
            $message = $parts[2] 
            $author = $parts[3]
            
            # Get file content at this commit
            $content = git show "$commit`:$file" 2>$null
            if (-not $content) { continue }
            
            # Quick filter - only include if it matches our patterns (if we have any)
            $matchesPattern = $true
            if ($searchPatterns) {
                $matchesPattern = $false
                foreach ($pattern in $searchPatterns) {
                    if ($content -match $pattern) {
                        $matchesPattern = $true
                        break
                    }
                }
            }
            
            if ($matchesPattern) {
                # Create temporary file for this version
                $safeFileName = $file -replace '[^\w.-]', '_'
                $tempFileName = "$safeFileName`_$($commit.Substring(0,8)).js"
                $tempPath = Join-Path $OutputDir $tempFileName
                
                $content | Set-Content $tempPath -Encoding UTF8
                
                $versionInfo = [PSCustomObject]@{
                    File = $file
                    Commit = $commit
                    Date = [DateTime]::Parse($date)
                    Message = $message
                    Author = $author
                    TempFilePath = $tempPath
                    Content = $content
                }
                
                $results += $versionInfo
            }
        }
    }
    
    return $results
}

function Parse-FileVersions {
    param(
        [array]$FileVersions,
        [string]$BaseClass,
        [string]$ClassName,
        [string]$FunctionName,
        [bool]$Globals,
        [bool]$Exports,
        [string]$Parser = "javascript-parser.js",
        [hashtable]$Config
    )

    $parserPath = Join-Path $PSScriptRoot "lib\parsers\$Parser"
    $parsedVersions = @()
    
    # Build extraction context from parameters
    $extractionContext = Build-ExtractionContext -Parameters @{
        BaseClass = $BaseClass
        ClassName = $ClassName
        FunctionName = $FunctionName
        Globals = $Globals
        Exports = $Exports
        FilePath = $FileVersions[0].File  # Use first file for context
    } -Config $Config
    
    foreach ($version in $FileVersions) {
        Write-Verbose "Parsing $($version.File) at commit $($version.Commit.Substring(0,8))"
        
        try {
            # Build parser arguments with extraction context
            $parserArgs = @($version.TempFilePath)
            
            # Pass extraction context as JSON
            $contextJson = $extractionContext | ConvertTo-Json -Depth 10 -Compress
            $parserArgs += @("--extraction-context", $contextJson)
            
            # Pass configuration if available
            if ($Config) {
                $configJson = $Config | ConvertTo-Json -Depth 10 -Compress
                $parserArgs += @("--language-config", $configJson)
            }
            
            # Run the parser
            $parseResult = node $parserPath @parserArgs | ConvertFrom-Json
            
            if ($parseResult -and $parseResult.segments -and $parseResult.segments.Count -gt 0) {
                # Filter segments based on extraction rules
                $filteredSegments = $parseResult.segments | Where-Object {
                    $include = $true
                    
                    # Apply exclusions for FilePath-only mode
                    if ($extractionContext.Exclusions -contains $_.type) {
                        $include = $false
                    }
                    
                    # Apply name filters
                    if ($extractionContext.Filters.Name -and $_.name -ne $extractionContext.Filters.Name) {
                        $include = $false
                    }
                    
                    # Apply extends filter
                    if ($extractionContext.Filters.Extends -and $_.extends -ne $extractionContext.Filters.Extends) {
                        $include = $false
                    }
                    
                    return $include
                }
                
                if ($filteredSegments.Count -gt 0) {
                    $version | Add-Member -MemberType NoteProperty -Name "ParsedSegments" -Value $filteredSegments
                $parsedVersions += $version
            }
            }
            
        } catch {
            Write-Warning "Failed to parse $($version.TempFilePath): $($_.Exception.Message)"
        }
    }
    
    return $parsedVersions
}

function Build-EvolutionTimeline {
    param(
        [array]$ParsedVersions,
        [string]$OutputDir
    )
    
    # Flatten all segments with their version info
    $allSegments = @()
    
    foreach ($version in $ParsedVersions) {
        foreach ($segment in $version.ParsedSegments) {
            $segmentData = [PSCustomObject]@{
                Name = $segment.name
                Type = $segment.type
                File = $version.File
                Commit = $version.Commit
                Date = $version.Date
                Author = $version.Author
                Message = $version.Message
                StartLine = $segment.startLine + 1  # Convert back to 1-based
                EndLine = $segment.endLine + 1
                LineCount = $segment.lineCount
                Content = $segment.content
                OriginalSegment = $segment
            }
            $allSegments += $segmentData
        }
    }
    
    # Group by name and type to create evolution chains
    $evolutionChains = $allSegments | Group-Object -Property Name,Type | ForEach-Object {
        $timeline = $_.Group | Sort-Object Date -Descending  # Most recent first
        
        [PSCustomObject]@{
            Name = $timeline[0].Name
            Type = $timeline[0].Type
            File = $timeline[0].File
            Versions = $timeline
            VersionCount = $timeline.Count
            FirstSeen = ($timeline | Sort-Object Date)[0].Date
            LastModified = $timeline[0].Date
            Changes = Get-EvolutionChanges -Timeline $timeline
        }
    }
    
    # Save evolution data
    $evolutionFile = Join-Path $OutputDir "evolution-timeline.json"
    $evolutionChains | ConvertTo-Json -Depth 10 | Set-Content $evolutionFile
    
    return $evolutionChains
}

function Get-EvolutionChanges {
    param([array]$Timeline)
    
    $changes = @()
    $sortedTimeline = $Timeline | Sort-Object Date
    
    for ($i = 1; $i -lt $sortedTimeline.Count; $i++) {
        $previous = $sortedTimeline[$i-1]
        $current = $sortedTimeline[$i]
        
        $change = [PSCustomObject]@{
            FromVersion = $i - 1
            ToVersion = $i
            Date = $current.Date
            Commit = $current.Commit
            Author = $current.Author
            Message = $current.Message
            LineCountChange = $current.LineCount - $previous.LineCount
            ContentChanged = $current.Content -ne $previous.Content
        }
        
        $changes += $change
    }
    
    return $changes
}

function Show-EvolutionResults {
    param(
        [array]$Evolution,
        [switch]$ShowDiffs
    )
    
    Write-Host "`nCODE EVOLUTION ANALYSIS RESULTS" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    
    $totalVersions = ($Evolution | ForEach-Object { $_.VersionCount } | Measure-Object -Sum).Sum
    Write-Host "Found $($Evolution.Count) code elements with $totalVersions total versions`n" -ForegroundColor Green
    
    foreach ($chain in $Evolution) {
        Write-Host "$('='*80)" -ForegroundColor DarkCyan
        Write-Host "$($chain.Type.ToUpper()): $($chain.Name)" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host "File: $($chain.File)" -ForegroundColor Gray
        Write-Host "Evolution: $($chain.VersionCount) versions from $($chain.FirstSeen.ToString('yyyy-MM-dd')) to $($chain.LastModified.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
        Write-Host "$('='*80)" -ForegroundColor DarkCyan
        
        if ($ShowDiffs -and $chain.Versions.Count -gt 1) {
            # Show recent versions
            $recentVersions = $chain.Versions | Select-Object -First 3
            
            foreach ($version in $recentVersions) {
                $versionIndex = [array]::IndexOf($chain.Versions, $version) + 1
                Write-Host "`n[$versionIndex] $($version.Date.ToString('yyyy-MM-dd HH:mm')) - $($version.Author)" -ForegroundColor Yellow
                Write-Host "    Commit: $($version.Commit.Substring(0,8))" -ForegroundColor Gray
                Write-Host "    Message: $($version.Message)" -ForegroundColor Gray
                Write-Host "    Lines: $($version.StartLine)-$($version.EndLine) ($($version.LineCount) lines)" -ForegroundColor Gray
            }
            
            # Show change summary
            if ($chain.Changes -and $chain.Changes.Count -gt 0) {
                Write-Host "`nRecent Changes:" -ForegroundColor Cyan
                $recentChanges = $chain.Changes | Sort-Object Date -Descending | Select-Object -First 3
                
                foreach ($change in $recentChanges) {
                    $changeColor = if ($change.LineCountChange -gt 0) { "Green" } elseif ($change.LineCountChange -lt 0) { "Red" } else { "Yellow" }
                    $changeText = if ($change.LineCountChange -ne 0) { " ($($change.LineCountChange) lines)" } else { " (modified)" }
                    
                    Write-Host "  $($change.Date.ToString('yyyy-MM-dd')): $($change.Message)$changeText" -ForegroundColor $changeColor
                }
            }
        }
        
        Write-Host ""
    }
}

function Get-ChainUnifiedDiff {
    param(
        [PSCustomObject]$Chain
    )
    
    if ($Chain.Versions.Count -le 1) {
        return "No evolution to display - single version only."
    }
    
    $diff = @"
=== $($Chain.Type.ToUpper()): $($Chain.Name) ===
File: $($Chain.File)
Evolution: $($Chain.VersionCount) versions
Timeline: $($Chain.FirstSeen.ToString('yyyy-MM-dd HH:mm')) to $($Chain.LastModified.ToString('yyyy-MM-dd HH:mm'))

"@
    
    # Sort versions chronologically (oldest first) for proper diff sequence
    $chronologicalVersions = $Chain.Versions | Sort-Object Date
    
    for ($i = 1; $i -lt $chronologicalVersions.Count; $i++) {
        $prevVersion = $chronologicalVersions[$i-1]
        $currVersion = $chronologicalVersions[$i]
        
        $diff += @"
@@ Version $i → Version $($i+1) ($($prevVersion.Date.ToString('yyyy-MM-dd HH:mm')) → $($currVersion.Date.ToString('yyyy-MM-dd HH:mm')))
Commit: $($currVersion.Commit.Substring(0,8)) by $($currVersion.Author)
Message: $($currVersion.Message)
Lines: $($prevVersion.LineCount) → $($currVersion.LineCount) ($($currVersion.LineCount - $prevVersion.LineCount) change)

"@
        
        # Generate unified diff between versions
        $versionDiff = Get-UnifiedDiff -Text1 $prevVersion.Content -Text2 $currVersion.Content
        $diff += $versionDiff + "`n`n"
    }
    
    return $diff
}

function Get-CompressedDiffText {
    param(
        [PSCustomObject]$Chain
    )

    if ($Chain.Versions.Count -le 1) {
        return "No evolution to display - single version only."
    }

    # Sort versions chronologically (oldest first)
    $chronologicalVersions = $Chain.Versions | Sort-Object Date

    # Collect all commit headers and changes
    $allHeaders = @()
    $changesByLine = @{}  # Hash table to store changes by line number

    # Process each version transition
    for ($i = 1; $i -lt $chronologicalVersions.Count; $i++) {
        $prevVersion = $chronologicalVersions[$i-1]
        $currVersion = $chronologicalVersions[$i]

        $fromCommit = $prevVersion.Commit.Substring(0, 7)
        $toCommit = $currVersion.Commit.Substring(0, 7)
        $allHeaders += "@@@ $fromCommit → $toCommit @@@"

        # Create temp files for git diff
        $tempFrom = [System.IO.Path]::GetTempFileName()
        $tempTo = [System.IO.Path]::GetTempFileName()

        try {
            $prevVersion.Content | Set-Content $tempFrom -Encoding UTF8
            $currVersion.Content | Set-Content $tempTo -Encoding UTF8

            # Generate zero-context diff using git
            $diffOutput = & git diff --no-index --unified=0 $tempFrom $tempTo 2>$null

            if ($LASTEXITCODE -ne 0) {
                # Parse the diff output
                $currentOldLine = 0
                $currentNewLine = 0

                foreach ($line in $diffOutput) {
                    # Parse hunk header: @@ -401,0 +402,5 @@
                    if ($line -match '^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@') {
                        $oldStart = [int]$matches[1]
                        $oldCount = if ($matches[2]) { [int]$matches[2] } else { 1 }
                        $newStart = [int]$matches[3]
                        $newCount = if ($matches[4]) { [int]$matches[4] } else { 1 }

                        $currentOldLine = $oldStart
                        $currentNewLine = $newStart
                    }
                    elseif ($line.StartsWith('-') -and -not $line.StartsWith('---')) {
                        # Deletion
                        $content = $line.Substring(1)
                        if (-not $changesByLine.ContainsKey($currentOldLine)) {
                            $changesByLine[$currentOldLine] = @()
                        }
                        $changesByLine[$currentOldLine] += @{
                            Type = 'delete'
                            Content = $content
                            Commit = $fromCommit
                            Line = $currentOldLine
                        }
                        $currentOldLine++
                    }
                    elseif ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
                        # Addition
                        $content = $line.Substring(1)
                        if (-not $changesByLine.ContainsKey($currentNewLine)) {
                            $changesByLine[$currentNewLine] = @()
                        }
                        $changesByLine[$currentNewLine] += @{
                            Type = 'add'
                            Content = $content
                            Commit = $toCommit
                            Line = $currentNewLine
                        }
                        $currentNewLine++
                    }
                }
            }
        }
        finally {
            Remove-Item $tempFrom -Force -ErrorAction SilentlyContinue
            Remove-Item $tempTo -Force -ErrorAction SilentlyContinue
        }
    }

    # Build the compressed output as plain text
    $output = ""

    # Add all commit headers at the top
    foreach ($header in $allHeaders) {
        $output += "$header`n"
    }
    $output += "`n"

    # Get the final version content
    $finalContent = $chronologicalVersions[-1].Content
    $finalLines = $finalContent -split "`n"

    # Output the final content with all changes inline
    for ($lineNum = 1; $lineNum -le $finalLines.Count; $lineNum++) {
        # First, show any changes for this line
        if ($changesByLine.ContainsKey($lineNum)) {
            foreach ($change in $changesByLine[$lineNum]) {
                if ($change.Type -eq 'delete') {
                    $output += "L$lineNum`: - $($change.Content)`n"
                }
                else {
                    $output += "L$lineNum`: + $($change.Content)`n"
                }
            }
        }

        # Then show the current line (if it exists in final version)
        if ($lineNum -le $finalLines.Count) {
            $output += "    $($finalLines[$lineNum - 1])`n"
        }
    }

    return $output
}

function Get-CompressedDiff {
    param(
        [PSCustomObject]$Chain
    )

    if ($Chain.Versions.Count -le 1) {
        return "No evolution to display - single version only."
    }

    # Sort versions chronologically (oldest first)
    $chronologicalVersions = $Chain.Versions | Sort-Object Date

    # Collect all commit headers and changes
    $allHeaders = @()
    $changesByLine = @{}  # Hash table to store changes by line number

    # Process each version transition
    for ($i = 1; $i -lt $chronologicalVersions.Count; $i++) {
        $prevVersion = $chronologicalVersions[$i-1]
        $currVersion = $chronologicalVersions[$i]

        $fromCommit = $prevVersion.Commit.Substring(0, 7)
        $toCommit = $currVersion.Commit.Substring(0, 7)
        $allHeaders += "@@@ $fromCommit → $toCommit @@@"

        # Create temp files for git diff
        $tempFrom = [System.IO.Path]::GetTempFileName()
        $tempTo = [System.IO.Path]::GetTempFileName()

        try {
            $prevVersion.Content | Set-Content $tempFrom -Encoding UTF8
            $currVersion.Content | Set-Content $tempTo -Encoding UTF8

            # Generate zero-context diff using git
            $diffOutput = & git diff --no-index --unified=0 $tempFrom $tempTo 2>$null

            if ($LASTEXITCODE -ne 0) {
                # Parse the diff output
                $currentOldLine = 0
                $currentNewLine = 0

                foreach ($line in $diffOutput) {
                    # Parse hunk header: @@ -401,0 +402,5 @@
                    if ($line -match '^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@') {
                        $oldStart = [int]$matches[1]
                        $oldCount = if ($matches[2]) { [int]$matches[2] } else { 1 }
                        $newStart = [int]$matches[3]
                        $newCount = if ($matches[4]) { [int]$matches[4] } else { 1 }

                        $currentOldLine = $oldStart
                        $currentNewLine = $newStart
                    }
                    elseif ($line.StartsWith('-') -and -not $line.StartsWith('---')) {
                        # Deletion
                        $content = $line.Substring(1)
                        if (-not $changesByLine.ContainsKey($currentOldLine)) {
                            $changesByLine[$currentOldLine] = @()
                        }
                        $changesByLine[$currentOldLine] += @{
                            Type = 'delete'
                            Content = $content
                            Commit = $fromCommit
                            Line = $currentOldLine
                        }
                        $currentOldLine++
                    }
                    elseif ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
                        # Addition
                        $content = $line.Substring(1)
                        if (-not $changesByLine.ContainsKey($currentNewLine)) {
                            $changesByLine[$currentNewLine] = @()
                        }
                        $changesByLine[$currentNewLine] += @{
                            Type = 'add'
                            Content = $content
                            Commit = $toCommit
                            Line = $currentNewLine
                        }
                        $currentNewLine++
                    }
                }
            }
        }
        finally {
            Remove-Item $tempFrom -Force -ErrorAction SilentlyContinue
            Remove-Item $tempTo -Force -ErrorAction SilentlyContinue
        }
    }

    # Build the compressed output
    $output = ""

    # Add all commit headers at the top
    foreach ($header in $allHeaders) {
        $output += "<div class='compressed-header'>$header</div>`n"
    }

    # Get the final version content
    $finalContent = $chronologicalVersions[-1].Content
    $finalLines = $finalContent -split "`n"

    # Output the final content with all changes inline
    $output += "<div style='margin-top: 10px; padding: 10px; background: rgb(0 0 0); border: 1px solid rgb(0 63 103); border-radius: 4px;'>`n" <# ##NeonSurge --bg-primary --border-subtle #>

    for ($lineNum = 1; $lineNum -le $finalLines.Count; $lineNum++) {
        # First, show any changes for this line
        if ($changesByLine.ContainsKey($lineNum)) {
            foreach ($change in $changesByLine[$lineNum]) {
                $escapedContent = [System.Web.HttpUtility]::HtmlEncode($change.Content)
                if ($change.Type -eq 'delete') {
                    $output += "<div class='diff-line diff-del'>L$lineNum`: - $escapedContent</div>`n"
                }
                else {
                    $output += "<div class='diff-line diff-add'>L$lineNum`: + $escapedContent</div>`n"
                }
            }
        }

        # Then show the current line (if it exists in final version)
        if ($lineNum -le $finalLines.Count) {
            $escapedLine = [System.Web.HttpUtility]::HtmlEncode($finalLines[$lineNum - 1])
            $output += "<div class='diff-line unchanged'>$escapedLine</div>`n"
        }
    }

    $output += "</div>"

    return $output
}

function Export-HtmlReport {
    param(
        [array]$Evolution,
        [string]$OutputDir
    )
    
    $reportPath = Join-Path $OutputDir "evolution-report.html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Code Evolution Report - Acorn Analysis</title>
    <style>
        body { font-family: 'Consolas', 'Monaco', monospace; background: rgb(0 0 0); color: rgb(255 255 255); margin: 0; padding: 20px; line-height: 1.6; } /*##NeonSurge --bg-primary --text-primary */
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: rgb(0 17 34); color: rgb(0 255 255); padding: 30px; border-radius: 8px; margin-bottom: 30px; text-align: center; border: 1px solid rgb(13 92 255); } /*##NeonSurge --bg-surface --text-secondary --border-default */
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: rgb(0 17 34); padding: 20px; border-radius: 6px; text-align: center; border: 1px solid rgb(0 63 103); } /*##NeonSurge --bg-surface --border-subtle */
        .stat-number { font-size: 2em; font-weight: bold; color: rgb(0 255 255); display: block; } /*##NeonSurge --secondary-300 (cyan) */
        .evolution-chain { background: rgb(0 0 0); margin: 20px 0; border-radius: 6px; overflow: hidden; border: 1px solid rgb(0 63 103); } /*##NeonSurge --bg-primary --border-subtle */
        .chain-header { background: rgb(13 13 42); padding: 20px; border-bottom: 1px solid rgb(13 92 255); } /*##NeonSurge --bg-secondary --border-default */
        .chain-title { font-size: 1.3em; font-weight: bold; color: rgb(0 255 255); margin-bottom: 5px; } /*##NeonSurge --secondary-300 (cyan) */
        .version { background: rgb(0 17 34); margin: 15px; padding: 15px; border-radius: 4px; border-left: 3px solid rgb(13 92 255); } /*##NeonSurge --bg-surface --secondary-500 */
        .version-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
        .version-info { color: rgb(136 255 255); } /*##NeonSurge --text-muted */
        .version-date { color: rgb(0 255 255); font-weight: bold; } /*##NeonSurge --text-secondary */
        .code-content { background: rgb(0 0 0); color: rgb(255 255 255); font-family: 'Consolas', monospace; padding: 15px; border-radius: 4px; overflow-x: auto; white-space: pre; font-size: 13px; margin-top: 10px; line-height: 1.5; border: 1px solid rgb(0 63 103); } /*##NeonSurge --bg-primary --text-primary --border-subtle */
        .changes-summary { background: rgb(0 17 34); padding: 15px; margin: 15px; border-radius: 4px; border-left: 4px solid rgb(255 204 0); } /*##NeonSurge --bg-surface --accent-500 */
        .change-item { margin: 5px 0; font-size: 0.9em; }
        .added { color: rgb(0 255 127); } /*##NeonSurge --success-200 */
        .removed { color: rgb(255 20 147); } /*##NeonSurge --primary-500 */
        .modified { color: rgb(255 204 0); } /*##NeonSurge --accent-500 */
        .toggle-btn { background: rgb(0 17 34); color: rgb(255 255 255); border: 1px solid rgb(0 63 103); padding: 6px 12px; border-radius: 3px; cursor: pointer; font-size: 11px; margin: 2px; } /*##NeonSurge --bg-surface --text-primary --border-subtle */
        .toggle-btn:hover { background: rgb(25 25 112); border-color: rgb(13 92 255); } /*##NeonSurge --bg-elevated --border-default */
        .diff-btn { background: rgb(13 92 255); color: white; border: 1px solid rgb(13 92 255); } /*##NeonSurge --secondary-500 */
        .diff-btn:hover { background: rgb(74 150 255); border-color: rgb(74 150 255); } /*##NeonSurge --secondary-600 */
        .code-content.collapsed { display: none; }
        .diff-container { display: none; background: rgb(0 0 0); border-radius: 4px; margin-top: 10px; border: 1px solid rgb(0 63 103); } /*##NeonSurge --bg-primary --border-subtle */
        .diff-container.active { display: block; }
        .diff-side-by-side { display: flex; position: relative; min-height: 300px; }
        .diff-side { flex: 1; min-width: 0; overflow-x: auto; font-family: 'Consolas', monospace; font-size: 13px; line-height: 1.4; }
        .diff-left { border-right: 1px solid rgb(0 63 103); } /*##NeonSurge --border-subtle */
        .diff-header { background: rgb(13 13 42); padding: 10px; text-align: center; font-weight: bold; color: rgb(255 255 255); position: sticky; top: 0; z-index: 10; } /*##NeonSurge --bg-secondary --text-primary */
        .diff-content { overflow-x: auto; max-height: 600px; overflow-y: auto; position: relative; }
        .diff-line { display: flex; margin: 0; padding: 0; min-height: 20px; }
        .diff-line-num { width: 50px; padding: 2px 8px; text-align: right; color: rgb(74 150 255); background: rgb(0 0 0); border-right: 1px solid rgb(0 63 103); user-select: none; flex-shrink: 0; font-size: 11px; } /*##NeonSurge --text-disabled --bg-primary --border-subtle */
        .diff-line-content { flex: 1; padding: 2px 12px; white-space: pre; overflow-x: visible; min-width: 0; }
        
        /* Color coding for different change types */
        .diff-line.diff-added { background: rgba(0, 255, 127, 0.2); } /*##NeonSurge --success-200 */
        .diff-line.diff-added .diff-line-num { background: rgba(0, 255, 127, 0.3); color: rgb(0 255 127); font-weight: bold; } /*##NeonSurge --success-200 */
        .diff-line.diff-added .diff-line-content { color: rgb(204 255 204); } /*##NeonSurge --success-50 */
        
        .diff-line.diff-removed { background: rgba(255, 20, 147, 0.2); } /*##NeonSurge --primary-500 */
        .diff-line.diff-removed .diff-line-num { background: rgba(255, 20, 147, 0.3); color: rgb(255 20 147); font-weight: bold; } /*##NeonSurge --primary-500 */
        .diff-line.diff-removed .diff-line-content { color: rgb(255 192 203); } /*##NeonSurge --primary-50 */
        
        .diff-line.diff-modified { background: rgba(255, 204, 0, 0.2); } /*##NeonSurge --accent-500 */
        .diff-line.diff-modified .diff-line-num { background: rgba(255, 204, 0, 0.3); color: rgb(255 204 0); font-weight: bold; } /*##NeonSurge --accent-500 */
        .diff-line.diff-modified .diff-line-content { color: rgb(255 243 160); } /*##NeonSurge --accent-50 */
        
        .diff-line.diff-unchanged .diff-line-content { color: rgb(255 255 255); } /*##NeonSurge --text-primary */
        .diff-line.diff-unchanged .diff-line-num { color: rgb(74 150 255); } /*##NeonSurge --text-disabled */
        
        /* Resizer between diff panels */
        .diff-resizer { width: 6px; background: rgb(0 63 103); cursor: col-resize; position: relative; flex-shrink: 0; } /*##NeonSurge --border-subtle */
        .diff-resizer:hover { background: rgb(13 92 255); } /*##NeonSurge --secondary-500 */
        .diff-resizer::after { content: '⋮'; color: rgb(74 150 255); position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-size: 12px; } /*##NeonSurge --text-disabled */
        
        .diff-stats { background: rgb(13 13 42); padding: 8px 15px; border-radius: 4px 4px 0 0; font-size: 12px; border-bottom: 1px solid rgb(0 63 103); } /*##NeonSurge --bg-secondary --border-subtle */
        .diff-stats .added { color: rgb(0 255 127); font-weight: bold; } /*##NeonSurge --success-200 */
        .diff-stats .removed { color: rgb(255 20 147); font-weight: bold; } /*##NeonSurge --primary-500 */
        .diff-stats .modified { color: rgb(255 204 0); font-weight: bold; } /*##NeonSurge --accent-500 */
        /* Copy button styling */
        .copy-btn {
            position: absolute;
            top: 10px;
            right: 10px;
            background: rgb(0 17 34); /*##NeonSurge --bg-surface */
            color: rgb(0 255 255);
            border: 1px solid rgb(0 63 103);
            padding: 6px 12px;
            border-radius: 3px;
            cursor: pointer;
            font-size: 12px;
            opacity: 0.8;
            transition: background 0.2s;
        }
        .copy-btn:hover {
            opacity: 1;
            background: rgb(13 92 255); /*##NeonSurge --secondary-500 */
            border-color: rgb(13 92 255);
        }
        .copy-btn.copied {
            background: rgb(0 255 127); /*##NeonSurge --success-200 */
            color: rgb(0 0 0);
        }
        .code-content {
            position: relative;
        }
        .code-content.collapsed .copy-btn {
            display: none;
        }

        /* Compressed Diff Styles - Neon Surge Theme (High Contrast) */
        .compressed-diff-btn {
            background: rgb(255 20 147);
            color: rgb(255 255 255);
            border: 1px solid rgb(255 20 147); /*##NeonSurge --primary-500 */
            padding: 8px 16px;
            border-radius: 3px;
            cursor: pointer;
            font-size: 14px;
            transition: background 0.2s ease;
        }
        .compressed-diff-btn:hover {
            background: rgb(255 63 132); /*##NeonSurge --primary-400 */
        }
        .compressed-header {
            background: rgb(13 13 42); /*##NeonSurge --bg-secondary */
            color: rgb(0 255 255); /*##NeonSurge --text-secondary */
            font-weight: bold;
            padding: 2px 12px;
            margin: 0; /* Remove spacing between headers */
            border-left: 3px solid rgb(255 20 147);
            font-size: 12px;
        }
        .diff-line.diff-del {
            background: rgba(255, 20, 147, 0.15); /*##NeonSurge --primary-500 */
            color: rgb(255 20 147);
            border-left: 2px solid rgb(255 20 147);
            padding: 0 8px; /* Tighter vertical spacing */
            margin: 0;
            line-height: 1.4; /* Consistent line height */
        }
        .diff-line.diff-add {
            background: rgba(0, 255, 127, 0.15); /*##NeonSurge --success-200 */
            color: rgb(0 255 127);
            border-left: 2px solid rgb(0 255 127);
            padding: 0 8px; /* Tighter vertical spacing */
            margin: 0;
            line-height: 1.4; /* Consistent line height */
        }
        .diff-line.unchanged {
            color: rgb(255 255 255); /*##NeonSurge --text-primary */
            opacity: 0.7;
            padding: 0 8px; /* Tighter vertical spacing */
            margin: 0;
            line-height: 1.4; /* Consistent line height */
        }
    </style>
    <script>
        function toggleCode(btn, targetId) {
            const content = document.getElementById(targetId);
            if (content.classList.contains('collapsed')) {
                content.classList.remove('collapsed');
                btn.textContent = 'Hide Code';
                addCopyButton(content);
            } else {
                content.classList.add('collapsed');
                btn.textContent = 'Show Code';
            }
        }
        
        function addCopyButton(container) {
            // Check if copy button already exists
            if (container.querySelector('.copy-btn')) {
                return;
            }
            
            const copyBtn = document.createElement('button');
            copyBtn.className = 'copy-btn';
            copyBtn.textContent = 'Copy';
            copyBtn.onclick = function() {
                copyToClipboard(container);
            };
            container.appendChild(copyBtn);
        }
        
        function copyToClipboard(container) {
            // Get the text content, excluding the copy button text
            const copyBtn = container.querySelector('.copy-btn');
            const originalText = copyBtn.textContent;
            
            // Temporarily remove button from DOM to get clean text
            copyBtn.style.display = 'none';
            const textToCopy = container.innerText;
            copyBtn.style.display = '';
            
            // Copy to clipboard
            navigator.clipboard.writeText(textToCopy).then(() => {
                // Visual feedback
                copyBtn.textContent = '✓ Copied!';
                copyBtn.classList.add('copied');
                
                // Reset after 2 seconds
                setTimeout(() => {
                    copyBtn.textContent = originalText;
                    copyBtn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                // Fallback method for older browsers
                const textArea = document.createElement('textarea');
                textArea.value = textToCopy;
                textArea.style.position = 'fixed';
                textArea.style.left = '-999999px';
                document.body.appendChild(textArea);
                textArea.select();
                try {
                    document.execCommand('copy');
                    copyBtn.textContent = '✓ Copied!';
                    copyBtn.classList.add('copied');
                    setTimeout(() => {
                        copyBtn.textContent = originalText;
                        copyBtn.classList.remove('copied');
                    }, 2000);
                } catch (err) {
                    copyBtn.textContent = 'Copy failed';
                    setTimeout(() => {
                        copyBtn.textContent = originalText;
                    }, 2000);
                }
                document.body.removeChild(textArea);
            });
        }
        
        function toggleDiff(btn, targetId) {
            const content = document.getElementById(targetId);
            if (content.classList.contains('active')) {
                content.classList.remove('active');
                btn.textContent = 'Show Diff';
            } else {
                content.classList.add('active');
                btn.textContent = 'Hide Diff';
                // Add copy buttons to diff panels if not already present
                const diffPanels = content.querySelectorAll('.diff-content');
                diffPanels.forEach(panel => {
                    if (!panel.querySelector('.copy-btn')) {
                        const copyBtn = document.createElement('button');
                        copyBtn.className = 'copy-btn';
                        copyBtn.textContent = 'Copy';
                        copyBtn.style.position = 'fixed';
                        copyBtn.style.zIndex = '1000';
                        copyBtn.onclick = function() {
                            copyDiffContent(panel);
                        };
                        panel.appendChild(copyBtn);
                    }
                });
            }
        }
        
        function copyDiffContent(panel) {
            const copyBtn = panel.querySelector('.copy-btn');
            const originalText = copyBtn.textContent;
            
            // Get all diff lines
            const lines = panel.querySelectorAll('.diff-line-content');
            const textToCopy = Array.from(lines).map(line => line.innerText).join('\n');
            
            navigator.clipboard.writeText(textToCopy).then(() => {
                copyBtn.textContent = '✓ Copied!';
                copyBtn.classList.add('copied');
                setTimeout(() => {
                    copyBtn.textContent = originalText;
                    copyBtn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                // Fallback for older browsers
                const textArea = document.createElement('textarea');
                textArea.value = textToCopy;
                textArea.style.position = 'fixed';
                textArea.style.left = '-999999px';
                document.body.appendChild(textArea);
                textArea.select();
                try {
                    document.execCommand('copy');
                    copyBtn.textContent = '✓ Copied!';
                    copyBtn.classList.add('copied');
                    setTimeout(() => {
                        copyBtn.textContent = originalText;
                        copyBtn.classList.remove('copied');
                    }, 2000);
                } catch (err) {
                    copyBtn.textContent = 'Failed';
                }
                document.body.removeChild(textArea);
            });
        }
        
        function computeDiff(text1, text2) {
            const lines1 = text1.split('\n');
            const lines2 = text2.split('\n');
            
            // Simple line-by-line diff algorithm
            const diff = [];
            let i = 0, j = 0;
            
            while (i < lines1.length || j < lines2.length) {
                if (i >= lines1.length) {
                    // Remaining lines in text2 are additions
                    diff.push({ type: 'added', content: lines2[j], line1: null, line2: j + 1 });
                    j++;
                } else if (j >= lines2.length) {
                    // Remaining lines in text1 are deletions
                    diff.push({ type: 'removed', content: lines1[i], line1: i + 1, line2: null });
                    i++;
                } else if (lines1[i] === lines2[j]) {
                    // Lines are identical
                    diff.push({ type: 'unchanged', content: lines1[i], line1: i + 1, line2: j + 1 });
                    i++;
                    j++;
                } else {
                    // Lines are different - look ahead to see if it's a modification or insertion/deletion
                    let found = false;
                    
                    // Look for line1[i] in upcoming lines2
                    for (let k = j + 1; k < Math.min(j + 5, lines2.length); k++) {
                        if (lines1[i] === lines2[k]) {
                            // Found it - lines2[j] to lines2[k-1] are additions
                            for (let l = j; l < k; l++) {
                                diff.push({ type: 'added', content: lines2[l], line1: null, line2: l + 1 });
                            }
                            diff.push({ type: 'unchanged', content: lines1[i], line1: i + 1, line2: k + 1 });
                            i++;
                            j = k + 1;
                            found = true;
                            break;
                        }
                    }
                    
                    if (!found) {
                        // Look for line2[j] in upcoming lines1
                        for (let k = i + 1; k < Math.min(i + 5, lines1.length); k++) {
                            if (lines2[j] === lines1[k]) {
                                // Found it - lines1[i] to lines1[k-1] are deletions
                                for (let l = i; l < k; l++) {
                                    diff.push({ type: 'removed', content: lines1[l], line1: l + 1, line2: null });
                                }
                                diff.push({ type: 'unchanged', content: lines2[j], line1: k + 1, line2: j + 1 });
                                i = k + 1;
                                j++;
                                found = true;
                                break;
                            }
                        }
                    }
                    
                    if (!found) {
                        // Treat as modification
                        diff.push({ type: 'modified', content1: lines1[i], content2: lines2[j], line1: i + 1, line2: j + 1 });
                        i++;
                        j++;
                    }
                }
            }
            
            return diff;
        }
        
        function renderDiff(diff, title1, title2) {
            const stats = { added: 0, removed: 0, modified: 0, unchanged: 0 };
            diff.forEach(d => stats[d.type]++);
            
            let html = '<div class="diff-stats">';
            html += '<strong>Changes: </strong>';
            html += '<span class="added">+' + stats.added + '</span> ';
            html += '<span class="removed">-' + stats.removed + '</span> ';
            html += '<span class="modified">~' + stats.modified + '</span>';
            html += '</div>';
            
            html += '<div class="diff-side-by-side">';
            
            // Left side
            html += '<div class="diff-side diff-left">';
            html += '<div class="diff-header">' + title1 + '</div>';
            html += '<div class="diff-content">';
            
            diff.forEach(d => {
                if (d.type === 'removed' || d.type === 'unchanged' || d.type === 'modified') {
                    const content = d.type === 'modified' ? d.content1 : d.content;
                    html += '<div class="diff-line diff-' + d.type + '">';
                    html += '<div class="diff-line-num">' + (d.line1 || '') + '</div>';
                    html += '<div class="diff-line-content">' + escapeHtml(content) + '</div>';
                    html += '</div>';
                } else if (d.type === 'added') {
                    // Empty line for alignment
                    html += '<div class="diff-line">';
                    html += '<div class="diff-line-num"></div>';
                    html += '<div class="diff-line-content"></div>';
                    html += '</div>';
                }
            });
            
            html += '</div></div>';
            
            // Resizer
            html += '<div class="diff-resizer" onmousedown="startResize(event)"></div>';
            
            // Right side  
            html += '<div class="diff-side">';
            html += '<div class="diff-header">' + title2 + '</div>';
            html += '<div class="diff-content">';
            
            diff.forEach(d => {
                if (d.type === 'added' || d.type === 'unchanged' || d.type === 'modified') {
                    const content = d.type === 'modified' ? d.content2 : d.content;
                    html += '<div class="diff-line diff-' + d.type + '">';
                    html += '<div class="diff-line-num">' + (d.line2 || '') + '</div>';
                    html += '<div class="diff-line-content">' + escapeHtml(content) + '</div>';
                    html += '</div>';
                } else if (d.type === 'removed') {
                    // Empty line for alignment
                    html += '<div class="diff-line">';
                    html += '<div class="diff-line-num"></div>';
                    html += '<div class="diff-line-content"></div>';
                    html += '</div>';
                }
            });
            
            html += '</div></div>';
            html += '</div>';
            
            return html;
        }
        
        // Resizer functionality
        let isResizing = false;
        let currentDiffContainer = null;
        
        function startResize(e) {
            isResizing = true;
            currentDiffContainer = e.target.parentElement;
            document.addEventListener('mousemove', doResize);
            document.addEventListener('mouseup', stopResize);
            e.preventDefault();
        }
        
        function doResize(e) {
            if (!isResizing || !currentDiffContainer) return;
            
            const containerRect = currentDiffContainer.getBoundingClientRect();
            const leftSide = currentDiffContainer.querySelector('.diff-left');
            const rightSide = currentDiffContainer.querySelector('.diff-side:last-child');
            
            if (leftSide && rightSide) {
                const percentage = ((e.clientX - containerRect.left) / containerRect.width) * 100;
                const clampedPercentage = Math.max(20, Math.min(80, percentage)); // Keep between 20% and 80%
                
                leftSide.style.flex = clampedPercentage / 100;
                rightSide.style.flex = (100 - clampedPercentage) / 100;
            }
        }
        
        function stopResize() {
            isResizing = false;
            currentDiffContainer = null;
            document.removeEventListener('mousemove', doResize);
            document.removeEventListener('mouseup', stopResize);
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        function showDiff(currentId, previousId, currentTitle, previousTitle, diffContainerId) {
            const currentElement = document.getElementById(currentId);
            const previousElement = document.getElementById(previousId);
            const diffContainer = document.getElementById(diffContainerId);
            
            if (!currentElement || !previousElement) return;
            
            const currentText = currentElement.textContent;
            const previousText = previousElement.textContent;
            
            const diff = computeDiff(previousText, currentText);
            const diffHtml = renderDiff(diff, previousTitle, currentTitle);
            
            diffContainer.innerHTML = diffHtml;
            
            // Set up scroll synchronization after the diff is rendered
            setTimeout(() => setupScrollSync(diffContainer), 50);
        }
        
        function setupScrollSync(diffContainer) {
            const leftContent = diffContainer.querySelector('.diff-left .diff-content');
            const rightContent = diffContainer.querySelector('.diff-side:last-child .diff-content');
            
            if (!leftContent || !rightContent) return;
            
            let isScrolling = false;
            
            function syncScroll(source, target) {
                if (isScrolling) return;
                isScrolling = true;
                
                target.scrollTop = source.scrollTop;
                target.scrollLeft = source.scrollLeft;
                
                setTimeout(() => { isScrolling = false; }, 10);
            }
            
            leftContent.addEventListener('scroll', () => {
                syncScroll(leftContent, rightContent);
            });
            
            rightContent.addEventListener('scroll', () => {
                syncScroll(rightContent, leftContent);
            });
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Code Evolution Report</h1>
            <p>Generated with Acorn AST analysis on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <span class="stat-number">$($Evolution.Count)</span>
                <div>Code Elements</div>
            </div>
            <div class="stat-card">
                <span class="stat-number">$(($Evolution | ForEach-Object { $_.VersionCount } | Measure-Object -Sum).Sum)</span>
                <div>Total Versions</div>
            </div>
            <div class="stat-card">
                <span class="stat-number">$(($Evolution | Group-Object Type).Count)</span>
                <div>Element Types</div>
            </div>
        </div>
"@

    $chainIndex = 0
    foreach ($chain in $Evolution) {
        $html += @"
        <div class="evolution-chain">
            <div class="chain-header">
                <div class="chain-title">$($chain.Type.ToUpper()): $($chain.Name)</div>
                <div>File: $($chain.File) | Versions: $($chain.VersionCount) | Evolution: $($chain.FirstSeen.ToString('yyyy-MM-dd')) to $($chain.LastModified.ToString('yyyy-MM-dd'))</div>
            </div>
"@
        
        $versionIndex = 0
        foreach ($version in $chain.Versions) {
            $codeId = "code_$chainIndex`_$versionIndex"
            $diffId = "diff_$chainIndex`_$versionIndex"
            $escapedContent = [System.Web.HttpUtility]::HtmlEncode($version.Content)
            
            $html += @"
            <div class="version">
                <div class="version-header">
                    <div class="version-info">
                        <span class="version-date">$($version.Date.ToString('yyyy-MM-dd HH:mm'))</span>
                        by $($version.Author) | 
                        Commit: $($version.Commit.Substring(0,8)) | 
                        Lines: $($version.StartLine)-$($version.EndLine) ($($version.LineCount) lines)
                    </div>
                    <div>
                        <button class="toggle-btn" onclick="toggleCode(this, '$codeId')">Show Code</button>
"@
            
            # Add diff button for versions that have a previous version
            if ($versionIndex -gt 0) {
                $prevCodeId = "code_$chainIndex`_$($versionIndex-1)"
                $prevVersion = $chain.Versions[$versionIndex-1]
                $currentTitle = "Current ($($version.Date.ToString('MM-dd HH:mm')))"
                $prevTitle = "Previous ($($prevVersion.Date.ToString('MM-dd HH:mm')))"
                
                $html += @"
                        <button class="toggle-btn diff-btn" onclick="showDiff('$codeId', '$prevCodeId', '$currentTitle', '$prevTitle', '$diffId'); toggleDiff(this, '$diffId')">Show Diff</button>
"@
            }
            # Add compressed diff button for the first (most recent) version
            elseif ($versionIndex -eq 0 -and $chain.Versions.Count -gt 1) {
                $compressedDiffId = "compressed_$chainIndex"
                $html += @"
                        <button class="compressed-diff-btn" onclick="toggleCode(this, '$compressedDiffId')">Show Compressed Diff</button>
"@
            }
            
            $html += @"
                    </div>
                </div>
                <div><em>$($version.Message)</em></div>
                <div class="code-content collapsed" id="$codeId">$escapedContent</div>
"@
            
            # Add compressed diff content for the first version
            if ($versionIndex -eq 0 -and $chain.Versions.Count -gt 1) {
                $compressedDiffId = "compressed_$chainIndex"
                $compressedDiffContent = Get-CompressedDiff -Chain $chain
                
                $html += @"
                <div class="code-content collapsed" id="$compressedDiffId">$compressedDiffContent</div>
"@
            }
            
            # Add diff container
            if ($versionIndex -gt 0) {
                $html += @"
                <div class="diff-container" id="$diffId"></div>
"@
            }
            
            $html += "</div>"
            $versionIndex++
        }
        
        if ($chain.Changes -and $chain.Changes.Count -gt 0) {
            $html += @"
            <div class="changes-summary">
                <h4>Changes Summary</h4>
"@
            foreach ($change in ($chain.Changes | Sort-Object Date -Descending | Select-Object -First 5)) {
                $changeClass = if ($change.LineCountChange -gt 0) { "added" } elseif ($change.LineCountChange -lt 0) { "removed" } else { "modified" }
                $changeText = if ($change.LineCountChange -ne 0) { " ($($change.LineCountChange) lines)" } else { ""  }
                
                $html += @"
                <div class="change-item">
                    <span class="$changeClass">$($change.Date.ToString('yyyy-MM-dd'))</span>: 
                    $($change.Message)$changeText
                </div>
"@
            }
            $html += "</div>"
        }
        
        $html += "</div>"
        $chainIndex++
    }

    $html += @"
    </div>
</body>
</html>
"@

    $html | Set-Content $reportPath -Encoding UTF8
    Write-Host "HTML report saved to: $reportPath" -ForegroundColor Green
}

function Export-CompressedDiff {
    param(
        [array]$Evolution,
        [string]$OutputDir
    )

    $reportPath = Join-Path $OutputDir "evolution-compressed-diff.txt"

    $report = @"
# Code Evolution - Compressed Diff Format
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#
# This file shows the complete evolution of code elements with all changes
# displayed inline. Each line that was ever modified is shown with its
# change history, followed by the final version.
#
# Format:
#   @@@ commit1 → commit2 @@@ : Version transition headers
#   L[n]: - content           : Line [n] was deleted
#   L[n]: + content           : Line [n] was added
#   content                   : Final version of the line
#
===============================================================================

"@

    foreach ($chain in $Evolution) {
        if ($chain.Versions.Count -gt 1) {
            $report += @"
=== $($chain.Type.ToUpper()): $($chain.Name) ===
File: $($chain.File)
Versions: $($chain.VersionCount)
Timeline: $($chain.FirstSeen.ToString('yyyy-MM-dd HH:mm')) to $($chain.LastModified.ToString('yyyy-MM-dd HH:mm'))

"@
            $compressedDiff = Get-CompressedDiffText -Chain $chain
            $report += $compressedDiff
            $report += "`n===============================================================================`n`n"
        }
    }

    $report | Set-Content $reportPath -Encoding UTF8
    Write-Host "Compressed diff report saved to: $reportPath" -ForegroundColor Green
}

function Export-UnifiedDiff {
    param(
        [array]$Evolution,
        [string]$OutputDir
    )

    $reportPath = Join-Path $OutputDir "evolution-unified-diff.txt"
    
    $report = @"
# Code Evolution - Unified Diff Format
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Optimized for LLM analysis of code evolution patterns
#
# This file shows the chronological evolution of code elements as unified diffs.
# Each section represents one code element's complete evolution journey.
# Use this format to analyze: functionality changes, architectural drift, 
# complexity evolution, lost/gained capabilities, etc.

===============================================================================

"@

    foreach ($chain in $Evolution) {
        $report += @"
=== $($chain.Type.ToUpper()): $($chain.Name) ===
File: $($chain.File)
Evolution: $($chain.VersionCount) versions
Timeline: $($chain.FirstSeen.ToString('yyyy-MM-dd HH:mm')) to $($chain.LastModified.ToString('yyyy-MM-dd HH:mm'))

"@
        
        if ($chain.Versions.Count -gt 1) {
            # Sort versions chronologically (oldest first) for proper diff sequence
            $chronologicalVersions = $chain.Versions | Sort-Object Date
            
            for ($i = 1; $i -lt $chronologicalVersions.Count; $i++) {
                $prevVersion = $chronologicalVersions[$i-1]
                $currVersion = $chronologicalVersions[$i]
                
                $report += @"
@@ Version $i → Version $($i+1) ($($prevVersion.Date.ToString('yyyy-MM-dd HH:mm')) → $($currVersion.Date.ToString('yyyy-MM-dd HH:mm')))
Commit: $($currVersion.Commit.Substring(0,8)) by $($currVersion.Author)
Message: $($currVersion.Message)
Lines: $($prevVersion.LineCount) → $($currVersion.LineCount) ($($currVersion.LineCount - $prevVersion.LineCount) change)

"@
                
                # Generate unified diff between versions
                $diff = Get-UnifiedDiff -Text1 $prevVersion.Content -Text2 $currVersion.Content
                $report += $diff + "`n`n"
            }
        } else {
            $report += @"
Single version - no evolution to display.

Initial version ($($chain.FirstSeen.ToString('yyyy-MM-dd HH:mm'))):
$($chain.Versions[0].Content)

"@
        }
        
        $report += "===============================================================================`n`n"
    }
    
    $report | Set-Content $reportPath -Encoding UTF8
    Write-Host "Unified diff report saved to: $reportPath" -ForegroundColor Green
}

function Get-UnifiedDiff {
    param(
        [string]$Text1,
        [string]$Text2
    )
    
    $lines1 = $Text1 -split "`n"
    $lines2 = $Text2 -split "`n"
    
    $diff = @()
    $i = 0
    $j = 0
    
    while ($i -lt $lines1.Length -or $j -lt $lines2.Length) {
        if ($i -ge $lines1.Length) {
            # Remaining lines in text2 are additions
            $diff += "+ $($lines2[$j])"
            $j++
        } elseif ($j -ge $lines2.Length) {
            # Remaining lines in text1 are deletions
            $diff += "- $($lines1[$i])"
            $i++
        } elseif ($lines1[$i] -eq $lines2[$j]) {
            # Lines are identical - include context
            $diff += "  $($lines1[$i])"
            $i++
            $j++
        } else {
            # Lines are different - look ahead to find the best match
            $found = $false
            
            # Look for line1[i] in upcoming lines2 (max 5 lines ahead)
            for ($k = $j + 1; $k -lt [Math]::Min($j + 6, $lines2.Length); $k++) {
                if ($lines1[$i] -eq $lines2[$k]) {
                    # Found matching line - lines2[j] to lines2[k-1] are additions
                    for ($l = $j; $l -lt $k; $l++) {
                        $diff += "+ $($lines2[$l])"
                    }
                    $diff += "  $($lines1[$i])"  # Context line
                    $i++
                    $j = $k + 1
                    $found = $true
                    break
                }
            }
            
            if (-not $found) {
                # Look for line2[j] in upcoming lines1 (max 5 lines ahead)
                for ($k = $i + 1; $k -lt [Math]::Min($i + 6, $lines1.Length); $k++) {
                    if ($lines2[$j] -eq $lines1[$k]) {
                        # Found matching line - lines1[i] to lines1[k-1] are deletions
                        for ($l = $i; $l -lt $k; $l++) {
                            $diff += "- $($lines1[$l])"
                        }
                        $diff += "  $($lines2[$j])"  # Context line
                        $i = $k + 1
                        $j++
                        $found = $true
                        break
                    }
                }
            }
            
            if (-not $found) {
                # No match found - treat as replacement
                $diff += "- $($lines1[$i])"
                $diff += "+ $($lines2[$j])"
                $i++
                $j++
            }
        }
    }
    
    return $diff -join "`n"
}

function Cleanup-TempFiles {
    param([string]$OutputDir)
    
    # Remove temporary JavaScript files
    Get-ChildItem $OutputDir -Filter "*.js" | Where-Object { $_.Name -match "_[a-f0-9]{8}\.js$" } | Remove-Item -Force
}

function Main {
    Write-Host "Code Evolution Tracker (Acorn-based)" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    # Create output directory
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    Write-Host "Output directory: $OutputDir" -ForegroundColor Green
    
    try {
        # Step 1: Find file versions in Git
        Write-Host "`nStep 1: Extracting file versions from Git history..." -ForegroundColor Yellow
        $fileVersions = Get-GitFileVersions `
            -BaseClass $BaseClass `
            -ClassName $ClassName `
            -FunctionName $FunctionName `
            -Globals $Globals `
            -Exports $Exports `
            -FilePath $FilePath `
            -OutputDir $OutputDir
        
        if (-not $fileVersions -or $fileVersions.Count -eq 0) {
            Write-Warning "No matching files found in Git history."
            return
        }
        
        Write-Host "Found $($fileVersions.Count) file versions" -ForegroundColor Green
        
        # Step 2: Parse with Acorn
        Write-Host "`nStep 2: Parsing with Acorn AST analysis..." -ForegroundColor Yellow
        $parsedVersions = Parse-FileVersions -FileVersions $fileVersions -BaseClass $BaseClass -ClassName $ClassName -Parser $Parser
        
        Write-Host "Successfully parsed $($parsedVersions.Count) versions" -ForegroundColor Green
        
        # Step 3: Build evolution timeline
        Write-Host "`nStep 3: Building evolution timeline..." -ForegroundColor Yellow
        $evolution = Build-EvolutionTimeline -ParsedVersions $parsedVersions -OutputDir $OutputDir
        
        Write-Host "Tracked evolution of $($evolution.Count) code elements" -ForegroundColor Green
        
        # Step 4: Show results
        Show-EvolutionResults -Evolution $evolution -ShowDiffs:$ShowDiffs
        
        # Step 5: Export if requested
        if ($ExportHtml) {
            Write-Host "`nStep 5: Exporting HTML report..." -ForegroundColor Yellow
            Export-HtmlReport -Evolution $evolution -OutputDir $OutputDir
        }
        
        if ($ExportUnifiedDiff) {
            Write-Host "`nExporting unified diff report..." -ForegroundColor Yellow
            Export-UnifiedDiff -Evolution $evolution -OutputDir $OutputDir
        }

        if ($ExportCompressedDiff) {
            Write-Host "`nExporting compressed diff report..." -ForegroundColor Yellow
            Export-CompressedDiff -Evolution $evolution -OutputDir $OutputDir
        }

        Write-Host "`nAnalysis complete! Results saved to: $OutputDir" -ForegroundColor Green
        
    } finally {
        # Cleanup
        Cleanup-TempFiles -OutputDir $OutputDir
    }
}

# Execute main function
Main