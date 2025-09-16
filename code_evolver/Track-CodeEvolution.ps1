#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Track code evolution across Git history with multi-language support and visual diff reporting

.DESCRIPTION
    This script analyzes code evolution through Git history using web-tree-sitter WASM parsers
    for accurate AST-based code extraction. Supports multiple languages (JavaScript, TypeScript,
    Python, Bash, PowerShell) with automatic language detection. Features enhanced compressed
    diff visualization using NeonSurge theme with intelligent shade-based commit differentiation.

.PARAMETER BaseClass
    Name of the base class to track inheritance from (e.g., "BaseService", "Component")

.PARAMETER ClassName
    Specific class name to track evolution of (e.g., "UserService", "LoginForm")

.PARAMETER FunctionName
    Track evolution of a specific function or method (e.g., "processData", "handleClick")

.PARAMETER Globals
    Track global variable assignments and window/globalThis properties

.PARAMETER Exports
    Track module exports (ES6 exports, module.exports, exports.*)

.PARAMETER FilePath
    Filter analysis to specific file(s). Supports wildcards (e.g., "src/*.js", "**/services/*.ts")

.PARAMETER OutputDir
    Directory to store analysis results (default: ./code-evolution-analysis)

.PARAMETER ConfigDir
    Directory containing language configuration files (default: ./config)

.PARAMETER Parser
    Parser to use for code analysis (default: tree-sitter-parser.js)
    Supports: tree-sitter-parser.js (auto-detects language), javascript-parser.js (Acorn fallback)

.PARAMETER ShowDiffs
    Display evolution diffs in console output

.PARAMETER ExportHtml
    Export results to interactive HTML report with NeonSurge theme

.PARAMETER ExportUnifiedDiff
    Export results to unified diff text format for LLM analysis

.PARAMETER ExportCompressedDiff
    Export compressed diff showing all changes inline with final version.
    Features intelligent shade-based commit coloring (shade 500 default, expanding
    range for multiple commits) and enhanced hover tooltips with commit metadata.

.PARAMETER Verbose
    Show detailed progress messages during execution

.PARAMETER SimpleCommitDisplay
    Opt-out flag to disable automatic enhancement of structured commit messages.
    By default, the script automatically detects and displays enhanced information
    for structured commits (JetBrains AI format, conventional commits, etc.).
    Use this flag to force simple commit message display only.

.EXAMPLE
    .\Track-CodeEvolution.ps1 -BaseClass "BaseService" -ShowDiffs
    # Track all classes extending BaseService

.EXAMPLE
    .\Track-CodeEvolution.ps1 -ClassName "UserService" -FilePath "src/services/*.js" -ExportHtml
    # Track UserService class in service files, export HTML report

.EXAMPLE
    .\Track-CodeEvolution.ps1 -FunctionName "handleRequest" -ExportCompressedDiff
    # Track handleRequest function evolution with compressed diff

.EXAMPLE
    .\Track-CodeEvolution.ps1 -FilePath "src/utils.py" -Parser "tree-sitter-parser.js" -ExportHtml
    # Analyze Python file with auto-detection, export HTML

.EXAMPLE
    .\Track-CodeEvolution.ps1 -Exports -FilePath "lib/*.js" -ExportUnifiedDiff
    # Track all exports in library files

.EXAMPLE
    .\Track-CodeEvolution.ps1 -ClassName "DataProcessor" -FilePath "R/*.R" -ExportHtml
    # Track R6/S3/S4 class evolution in R files

.NOTES
    Supported Languages:
    - JavaScript/TypeScript (.js, .jsx, .ts, .tsx, .mjs, .cjs)
    - Python (.py, .pyw)
    - Bash (.sh, .bash)
    - PowerShell (.ps1, .psm1, .psd1)
    - R (.r, .R) - Supports R6, S3, S4 classes and methods

    Requirements:
    - Git repository
    - Node.js installed
    - web-tree-sitter (auto-installed on first run)

    Output Files:
    - evolution-report.html: Interactive visual report with commit shading
    - evolution-unified-diff.txt: Traditional chronological diffs
    - evolution-compressed-diff.txt: Inline changes with final code
    - evolution-timeline.json: Raw evolution data

    Shade Calculation for Commits:
    - 1 commit: shade 500 (default)
    - 2 commits: shades 400, 600
    - 3 commits: shades 400, 500, 600
    - 4-5 commits: expands to 300-700 range
    - 6-8 commits: expands to 200-800 range
    - 9+ commits: uses full 100-900 range
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
    [string]$Parser = "tree-sitter-parser.js",  # Universal parser with auto language detection
    [switch]$ShowDiffs,
    [switch]$ExportHtml,
    [switch]$ExportUnifiedDiff,
    [switch]$ExportCompressedDiff,
    [switch]$Verbose,
    [switch]$SimpleCommitDisplay,  # Opt-out flag to disable automatic enhancement
    [switch]$NoComponentFiltering  # Disable component filtering (show all commits equally)
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

function Parse-CommitMessage {
    param(
        [string]$Message,
        [string]$CommitHash,
        [string]$Author,
        [datetime]$Date,
        [string]$GitNotes = $null
    )

    $result = @{
        Raw = $Message
        Notes = $GitNotes
        Type = "unknown"
        Scope = $null
        Summary = $Message
        Components = @()
        Actions = @()
        IsStructured = $false
        ConventionalType = $null
        SemanticInfo = @{}
        CommitHash = $CommitHash
        Author = $Author
        Date = $Date
    }

    # Parse structured format (JetBrains AI): type(scope): summary\n\n[component] ACTION: description
    if ($Message -match '^(\w+)(?:\(([^)]+)\))?: (.+)') {
        $result.ConventionalType = $matches[1]
        $result.Scope = $matches[2]
        $result.Summary = $matches[3]

        # Look for component changes in message body
        $lines = $Message -split "`n"
        foreach ($line in $lines) {
            if ($line -match '^\[([^\]]+)\]\s+(NEW|MODIFIED|REMOVED|RENAMED|MOVED):\s*(.+)') {
                $component = @{
                    Name = $matches[1]
                    Action = $matches[2]
                    Description = $matches[3]
                }
                $result.Components += $component
                $result.Actions += $matches[2]
                $result.IsStructured = $true
            }
        }
    }

    # Parse git notes with same logic if present
    if ($GitNotes) {
        $noteLines = $GitNotes -split "`n"
        foreach ($line in $noteLines) {
            if ($line -match '^\[([^\]]+)\]\s+(NEW|MODIFIED|REMOVED|RENAMED|MOVED):\s*(.+)') {
                $component = @{
                    Name = $matches[1]
                    Action = $matches[2]
                    Description = $matches[3]
                    FromNotes = $true
                }
                $result.Components += $component
                $result.Actions += $matches[2]
                $result.IsStructured = $true
            }
        }
    }

    # Detect common semantic patterns if not structured
    if (-not $result.IsStructured) {
        # Common action patterns
        $actionPatterns = @{
            'add|create|implement|introduce' = 'addition'
            'fix|repair|resolve|correct' = 'fix'
            'update|modify|change|enhance' = 'modification'
            'remove|delete|drop|clean' = 'removal'
            'refactor|restructure|reorganize' = 'refactor'
            'test|spec' = 'test'
            'doc|document|readme' = 'documentation'
        }

        $lowerMessage = $Message.ToLower()
        foreach ($pattern in $actionPatterns.Keys) {
            if ($lowerMessage -match $pattern) {
                $result.SemanticInfo.ActionType = $actionPatterns[$pattern]
                break
            }
        }
    }

    # Unique actions
    $result.Actions = $result.Actions | Select-Object -Unique

    return $result
}

function Group-CommitMessages {
    param(
        [array]$ParsedCommits
    )

    $groups = @()

    # Group by component + action for structured commits
    $structuredCommits = $ParsedCommits | Where-Object { $_.IsStructured }
    if ($structuredCommits) {
        $componentGroups = @{}
        foreach ($commit in $structuredCommits) {
            foreach ($component in $commit.Components) {
                $key = "$($component.Name):$($component.Action)"
                if (-not $componentGroups.ContainsKey($key)) {
                    $componentGroups[$key] = @{
                        ComponentName = $component.Name
                        Action = $component.Action
                        Commits = @()
                        Descriptions = @()
                    }
                }
                $componentGroups[$key].Commits += $commit
                $componentGroups[$key].Descriptions += $component.Description
            }
        }

        foreach ($key in $componentGroups.Keys) {
            $group = $componentGroups[$key]
            $groups += @{
                Type = 'component'
                Summary = "$($group.Commits.Count) commits: $($group.ComponentName) $($group.Action.ToLower())"
                ComponentName = $group.ComponentName
                Action = $group.Action
                Commits = $group.Commits
                Descriptions = $group.Descriptions | Select-Object -Unique
            }
        }
    }

    # Group by conventional type + scope
    $conventionalCommits = $ParsedCommits | Where-Object { $_.ConventionalType -and -not $_.IsStructured }
    if ($conventionalCommits) {
        $typeGroups = $conventionalCommits | Group-Object -Property ConventionalType,Scope
        foreach ($typeGroup in $typeGroups) {
            $type = $typeGroup.Group[0].ConventionalType
            $scope = $typeGroup.Group[0].Scope
            $scopeText = if ($scope) { "($scope)" } else { "" }

            $groups += @{
                Type = 'conventional'
                Summary = "$($typeGroup.Count) commits: $type$scopeText"
                ConventionalType = $type
                Scope = $scope
                Commits = $typeGroup.Group
            }
        }
    }

    # Group by semantic action type
    $semanticCommits = $ParsedCommits | Where-Object {
        $_.SemanticInfo.ActionType -and -not $_.IsStructured -and -not $_.ConventionalType
    }
    if ($semanticCommits) {
        $semanticGroups = $semanticCommits | Group-Object -Property { $_.SemanticInfo.ActionType }
        foreach ($semanticGroup in $semanticGroups) {
            $actionType = $semanticGroup.Group[0].SemanticInfo.ActionType

            $groups += @{
                Type = 'semantic'
                Summary = "$($semanticGroup.Count) commits: $actionType"
                ActionType = $actionType
                Commits = $semanticGroup.Group
            }
        }
    }

    # Add ungrouped commits
    $ungroupedCommits = $ParsedCommits | Where-Object {
        -not $_.IsStructured -and -not $_.ConventionalType -and -not $_.SemanticInfo.ActionType
    }
    if ($ungroupedCommits) {
        $groups += @{
            Type = 'ungrouped'
            Summary = "$($ungroupedCommits.Count) other commits"
            Commits = $ungroupedCommits
        }
    }

    return $groups
}

function Filter-CommitsByComponent {
    param(
        [string]$ComponentName,
        [array]$ParsedCommits
    )

    # Filter commits that specifically mention this component
    $componentCommits = @()

    foreach ($commit in $ParsedCommits) {
        $hasComponent = $false

        foreach ($component in $commit.Components) {
            if ($component.Name -eq $ComponentName) {
                $hasComponent = $true
                # Add the specific component info to the commit for easy access
                if (-not $commit.RelevantComponents) {
                    $commit | Add-Member -MemberType NoteProperty -Name "RelevantComponents" -Value @()
                }
                $commit.RelevantComponents += $component
            }
        }

        if ($hasComponent) {
            $componentCommits += $commit
        }
    }

    return $componentCommits
}

function Get-GitNotes {
    param(
        [string]$CommitHash
    )

    try {
        $notes = & git notes show $CommitHash 2>$null
        if ($LASTEXITCODE -eq 0 -and $notes) {
            return ($notes -join "`n")
        }
    }
    catch {
        # No notes for this commit or git notes not initialized
        Write-Verbose "No git notes found for commit $($CommitHash.Substring(0,8))"
    }

    return $null
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
        $commitIndex++  # Increment for next commit pair
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
        $commitIndex++  # Increment for next commit pair
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
        # Normalize path for Git (convert backslashes to forward slashes and remove leading .\ or .\)
        $normalizedPath = $FilePath -replace '^\.\\', '' -replace '^\./', '' -replace '\\', '/'
        Write-Verbose "Original path: $FilePath"
        Write-Verbose "Normalized path: $normalizedPath"
        $relevantFiles = @($normalizedPath)
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
    if ($VerbosePreference -eq 'Continue' -and $relevantFiles.Count -gt 0) {
        Write-Verbose "Files to process:"
        foreach ($f in $relevantFiles) {
            Write-Verbose "  - $f"
        }
    }
    
    # For each file, get all versions
    foreach ($file in $relevantFiles) {
        Write-Verbose "Processing file: $file"

        # Get commit history for this file
        Write-Verbose "  Running: git log --follow --pretty=format:'%H|%ai|%s|%an' -- $file"
        $commits = git log --follow --pretty=format:"%H|%ai|%s|%an" -- $file
        
        if (-not $commits) {
            Write-Verbose "  No commits found for file: $file"
            continue
        }
        $commitCount = @($commits).Count
        Write-Verbose "  Found $commitCount commits for file: $file"
        
        foreach ($commitLine in $commits) {
            if ([string]::IsNullOrWhiteSpace($commitLine)) { continue }
            
            $parts = $commitLine -split '\|', 4
            if ($parts.Count -lt 4) { continue }
            
            $commit = $parts[0]
            $date = $parts[1]
            $message = $parts[2] 
            $author = $parts[3]
            
            # Get file content at this commit
            if ($VerbosePreference -eq 'Continue') {
                Write-Verbose "  Extracting content from commit: $($commit.Substring(0,7))"
            }
            $content = git show "$commit`:$file" 2>$null
            if (-not $content) {
                Write-Verbose "    No content found for commit: $($commit.Substring(0,7))"
                continue
            }
            
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
                # Create temporary file for this version, preserving original extension
                $safeFileName = $file -replace '[^\w.-]', '_'
                # Extract the original extension from the file
                $extension = [System.IO.Path]::GetExtension($file)
                if (-not $extension) { $extension = ".txt" }  # Default to .txt if no extension
                $tempFileName = "$safeFileName`_$($commit.Substring(0,8))$extension"
                $tempPath = Join-Path $OutputDir $tempFileName
                
                $content | Set-Content $tempPath -Encoding UTF8
                
                # Always try to get git notes - it's fast and returns null if none exist
                $gitNotes = Get-GitNotes -CommitHash $commit

                $versionInfo = [PSCustomObject]@{
                    File = $file
                    Commit = $commit
                    Date = [DateTime]::Parse($date)
                    Message = $message
                    Author = $author
                    GitNotes = $gitNotes
                    TempFilePath = $tempPath
                    Content = $content
                }

                $results += $versionInfo
            }
        }
        $commitIndex++  # Increment for next commit pair
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
        [string]$Parser = "tree-sitter-parser.js",
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
        if ($VerbosePreference -eq 'Continue') {
            Write-Verbose "  Date: $($version.Date)"
            Write-Verbose "  Author: $($version.Author)"
            if ($version.Segments) {
                $segmentGroups = $version.Segments | Group-Object type
                Write-Verbose "  Segments found: $($segmentGroups.Name -join ', ')"
            }
        }
        
        try {
            # Build parser arguments with extraction context
            $parserArgs = @($version.TempFilePath)
            
            # Write extraction context to temp file to avoid quote escaping issues
            $contextFile = [System.IO.Path]::GetTempFileName()
            $contextJson = $extractionContext | ConvertTo-Json -Depth 10 -Compress
            # Use UTF8 without BOM to avoid JSON parsing issues
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($contextFile, $contextJson, $utf8NoBom)

            # Build command line arguments
            $nodeArgs = @($parserPath, $version.TempFilePath, "--extraction-context", "@$contextFile")

            # Pass configuration if available
            if ($Config) {
                $configFile = [System.IO.Path]::GetTempFileName()
                $configJson = $Config | ConvertTo-Json -Depth 10 -Compress
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($configFile, $configJson, $utf8NoBom)
                $nodeArgs += @("--language-config", "@$configFile")
            }

            # Run the parser
            $parseResult = & node @nodeArgs | ConvertFrom-Json

            # Clean up temp files
            Remove-Item -Path $contextFile -ErrorAction SilentlyContinue
            if ($configFile) { Remove-Item -Path $configFile -ErrorAction SilentlyContinue }
            
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
        $commitIndex++  # Increment for next commit pair
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
                GitNotes = $version.GitNotes
                StartLine = $segment.startLine + 1  # Convert back to 1-based
                EndLine = $segment.endLine + 1
                LineCount = $segment.lineCount
                Content = $segment.content
                OriginalSegment = $segment
            }
            $allSegments += $segmentData
        }
        $commitIndex++  # Increment for next commit pair
    }
    
    # Group by name and type to create evolution chains
    $evolutionChains = $allSegments | Group-Object -Property Name,Type | ForEach-Object {
        $allVersions = $_.Group | Sort-Object Date  # Chronological order for comparison

        # Filter for versions with actual content differences
        $meaningfulVersions = @()
        $lastVersion = $null

        foreach ($version in $allVersions) {
            if ($lastVersion -eq $null) {
                # Always include first version
                $meaningfulVersions += $version
                $lastVersion = $version
            } else {
                # Compare content using git diff with whitespace ignore
                $tempFrom = [System.IO.Path]::GetTempFileName()
                $tempTo = [System.IO.Path]::GetTempFileName()

                try {
                    $lastVersion.Content | Set-Content $tempFrom -Encoding UTF8
                    $version.Content | Set-Content $tempTo -Encoding UTF8

                    # Capture the full diff output for later use
                    $diffOutput = & git diff --no-index --unified=0 --ignore-all-space $tempFrom $tempTo 2>$null

                    if ($LASTEXITCODE -ne 0) {
                        # Diff found differences - include this version and store diff data
                        $version | Add-Member -MemberType NoteProperty -Name "DiffFromPrevious" -Value $diffOutput
                        $version | Add-Member -MemberType NoteProperty -Name "PreviousVersion" -Value $lastVersion
                        $meaningfulVersions += $version
                        $lastVersion = $version
                    }
                } finally {
                    Remove-Item -Path $tempFrom -ErrorAction SilentlyContinue
                    Remove-Item -Path $tempTo -ErrorAction SilentlyContinue
                }
            }
        }

        # Only create chain if we have meaningful versions
        if ($meaningfulVersions.Count -gt 0) {
            $timeline = $meaningfulVersions | Sort-Object Date -Descending  # Most recent first

            $chain = [PSCustomObject]@{
                Name = $timeline[0].Name
                Type = $timeline[0].Type
                File = $timeline[0].File
                Versions = $timeline
                VersionCount = $timeline.Count
                FirstSeen = ($timeline | Sort-Object Date)[0].Date
                LastModified = $timeline[0].Date
                Changes = Get-EvolutionChanges -Timeline $timeline
                OriginalVersionCount = $allVersions.Count
            }

            # Always parse commit messages - it's lightweight and provides automatic enhancement
            $parsedCommits = @()
            foreach ($version in $timeline) {
                $parsed = Parse-CommitMessage -Message $version.Message `
                    -CommitHash $version.Commit `
                    -Author $version.Author `
                    -Date $version.Date `
                    -GitNotes $version.GitNotes
                $parsed | Add-Member -MemberType NoteProperty -Name "Version" -Value $version
                $parsedCommits += $parsed
            }

            # Always group commits - grouping logic handles all message formats
            $commitGroups = Group-CommitMessages -ParsedCommits $parsedCommits

            # Filter commits that specifically mention this component
            $componentCommits = Filter-CommitsByComponent -ComponentName $chain.Name -ParsedCommits $parsedCommits

            # Always add the analysis (used automatically when structured data exists)
            $chain | Add-Member -MemberType NoteProperty -Name "CommitGroups" -Value $commitGroups
            $chain | Add-Member -MemberType NoteProperty -Name "ParsedCommits" -Value $parsedCommits
            $chain | Add-Member -MemberType NoteProperty -Name "ComponentCommits" -Value $componentCommits

            $chain
        }
        $commitIndex++  # Increment for next commit pair
    } | Where-Object { $_ -ne $null }
    
    # Save evolution data (use high depth to avoid truncation warning)
    $evolutionFile = Join-Path $OutputDir "evolution-timeline.json"
    $evolutionChains | ConvertTo-Json -Depth 20 | Set-Content $evolutionFile
    
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

    # Process each version that has cached diff data
    $commitIndex = 0
    foreach ($version in $chronologicalVersions | Where-Object { $_.DiffFromPrevious }) {
        $fromCommit = $version.PreviousVersion.Commit.Substring(0, 7)
        $toCommit = $version.Commit.Substring(0, 7)
        $allHeaders += "@@@ $fromCommit → $toCommit @@@"

        # Use the cached diff output instead of running git diff again
        $diffOutput = $version.DiffFromPrevious

        # Parse the cached diff output
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
                            FromCommit = $fromCommit
                            ToCommit = $toCommit
                            CommitMessage = $commitMessage
                            CommitAuthor = $commitAuthor
                            CommitDate = $commitDate
                            ShadeValue = $shadeValue
                            Line = $currentOldLine
                            VersionIndex = $versionIdx
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
                            FromCommit = $fromCommit
                            ToCommit = $toCommit
                            CommitMessage = $commitMessage
                            CommitAuthor = $commitAuthor
                            CommitDate = $commitDate
                            ShadeValue = $shadeValue
                            Line = $currentNewLine
                            VersionIndex = $versionIdx
                        }
                        $currentNewLine++
                    }
        }
        $commitIndex++  # Increment for next commit pair
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
        #$commitIndex++  # Increment for next commit pair
    }

    return $output
}

function Get-CompressedDiff {
    param(
        [PSCustomObject]$Chain,
        [int]$ChainIndex
    )

    if ($Chain.Versions.Count -le 1) {
        return "No evolution to display - single version only."
    }

    # Sort versions chronologically (oldest first)
    $chronologicalVersions = $Chain.Versions | Sort-Object Date

    # Collect all commit headers and changes
    $allHeaders = @()
    $changesByLine = @{}  # Hash table to store changes by line number

    # Calculate total unique commits for shade mapping
    $totalCommits = ($chronologicalVersions | Where-Object { $_.DiffFromPrevious }).Count

    # Function to calculate shade value based on commit index and total commits
    function Get-ShadeValue {
        param(
            [int]$CommitIndex,
            [int]$TotalCommits
        )

        $shades = @(100, 200, 300, 400, 500, 600, 700, 800, 900)

        if ($TotalCommits -eq 1) {
            return 500  # Single commit uses default shade
        }
        elseif ($TotalCommits -eq 2) {
            return @(400, 600)[$CommitIndex]
        }
        elseif ($TotalCommits -eq 3) {
            return @(400, 500, 600)[$CommitIndex]
        }
        elseif ($TotalCommits -eq 4) {
            return @(300, 400, 600, 700)[$CommitIndex]
        }
        elseif ($TotalCommits -eq 5) {
            return @(300, 400, 500, 600, 700)[$CommitIndex]
        }
        elseif ($TotalCommits -eq 6) {
            return @(200, 300, 400, 600, 700, 800)[$CommitIndex]
        }
        elseif ($TotalCommits -eq 7) {
            return @(200, 300, 400, 500, 600, 700, 800)[$CommitIndex]
        }
        elseif ($TotalCommits -eq 8) {
            return @(200, 300, 400, 500, 600, 700, 800, 900)[$CommitIndex]
        }
        else {
            # For 9+ commits, use all shades
            $shadeIndex = [Math]::Min($CommitIndex, 8)
            return $shades[$shadeIndex]
        }
    }

    # Process each version that has cached diff data
    $commitIndex = 0
    $versionIndices = @{}  # Map versions to their indices in the chain
    for ($i = 0; $i -lt $Chain.Versions.Count; $i++) {
        $versionIndices[$Chain.Versions[$i].Commit] = $i
    }

    foreach ($version in $chronologicalVersions | Where-Object { $_.DiffFromPrevious }) {
        $fromCommit = $version.PreviousVersion.Commit.Substring(0, 7)
        $toCommit = $version.Commit.Substring(0, 7)
        $commitMessage = $version.Message
        $commitAuthor = $version.Author
        $commitDate = $version.Date.ToString('yyyy-MM-dd HH:mm')
        $shadeValue = Get-ShadeValue -CommitIndex $commitIndex -TotalCommits $totalCommits

        # Find the version index in the chain (descending order)
        $versionIdx = $versionIndices[$version.Commit]

        # Store header with metadata for later use
        $allHeaders += @{
            Text = "@@@ $fromCommit → $toCommit @@@"
            FromCommit = $fromCommit
            ToCommit = $toCommit
            Version = $version
            VersionIndex = $versionIdx
            ShadeValue = $shadeValue
        }

        # Use the cached diff output instead of running git diff again
        $diffOutput = $version.DiffFromPrevious

        # Parse the cached diff output
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
                            FromCommit = $fromCommit
                            ToCommit = $toCommit
                            CommitMessage = $commitMessage
                            CommitAuthor = $commitAuthor
                            CommitDate = $commitDate
                            ShadeValue = $shadeValue
                            Line = $currentOldLine
                            VersionIndex = $versionIdx
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
                            FromCommit = $fromCommit
                            ToCommit = $toCommit
                            CommitMessage = $commitMessage
                            CommitAuthor = $commitAuthor
                            CommitDate = $commitDate
                            ShadeValue = $shadeValue
                            Line = $currentNewLine
                            VersionIndex = $versionIdx
                        }
                        $currentNewLine++
                    }
        }
        $commitIndex++  # Increment for next commit pair
    }

    # Build the compressed output
    $output = ""

    # Get centralized shade color definitions
    $shadeColors = Get-ShadeColorDefinitions
    $addShadeColors = $shadeColors.Add
    $delShadeColors = $shadeColors.Del

    # Add all commit headers at the top with colored indicators
    foreach ($header in $allHeaders) {
        $diffId = "diff_${ChainIndex}_$($header.VersionIndex)"
        $shade = $header.ShadeValue
        $addColors = $addShadeColors[$shade]
        $delColors = $delShadeColors[$shade]

        $headerHtml = "<div class='compressed-header'>"
        $headerHtml += "$($header.Text) "
        # Added indicator with shade-specific colors
        $headerHtml += "<span style='background: $($addColors.bg); color: $($addColors.color); padding: 2px 6px; border-radius: 3px; cursor: pointer; margin-left: 8px; font-weight: bold;' onclick='showDiffFromCompressed(""$diffId"")'><strong>+</strong> added</span> "
        # Deleted indicator with shade-specific colors
        $headerHtml += "<span style='background: $($delColors.bg); color: $($delColors.color); padding: 2px 6px; border-radius: 3px; cursor: pointer; font-weight: bold;' onclick='showDiffFromCompressed(""$diffId"")'><strong>−</strong> deleted</span>"
        $headerHtml += "</div>"
        $output += $headerHtml
    }

    # Get the final version content
    $finalContent = $chronologicalVersions[-1].Content
    $finalLines = $finalContent -split "`n"

    # Output the final content with all changes inline
    $output += "<div class='compressed-content' style='margin-top: 10px; padding: 10px; background: rgb(0 0 0); border: 1px solid rgb(0 63 103); border-radius: 4px;'>" <# ##NeonSurge --bg-primary --border-subtle #>

    for ($lineNum = 1; $lineNum -le $finalLines.Count; $lineNum++) {
        # First, show any changes for this line
        if ($changesByLine.ContainsKey($lineNum)) {
            foreach ($change in $changesByLine[$lineNum]) {
                $escapedContent = [System.Web.HttpUtility]::HtmlEncode($change.Content)
                $shadeClass = "shade-$($change.ShadeValue)"
                # Create safe tooltip text
                $safeMessage = $change.CommitMessage -replace '"', '&quot;' -replace "'", '&apos;'
                $tooltipText = "$($change.ToCommit): $safeMessage by $($change.CommitAuthor) at $($change.CommitDate)"
                $diffId = "diff_${ChainIndex}_$($change.VersionIndex)"

                if ($change.Type -eq 'delete') {
                    $output += "<div class='diff-line diff-del $shadeClass' title='$tooltipText' style='cursor: pointer;' onclick='showDiffFromCompressed(""$diffId"")'><span class='line-num'>L$lineNum</span>: - $escapedContent</div>"
                }
                else {
                    $output += "<div class='diff-line diff-add $shadeClass' title='$tooltipText' style='cursor: pointer;' onclick='showDiffFromCompressed(""$diffId"")'><span class='line-num'>L$lineNum</span>: + $escapedContent</div>"
                }
            }
        }

        # Then show the current line (if it exists in final version) with line number
        if ($lineNum -le $finalLines.Count) {
            $escapedLine = [System.Web.HttpUtility]::HtmlEncode($finalLines[$lineNum - 1])
            $output += "<div class='diff-line unchanged'><span class='line-num-unchanged'>$lineNum</span>: = $escapedLine</div>"
        }
    }

    $output += "</div>"

    return $output
}

function Get-ShadeColorDefinitions {
    # Define shade-specific colors for additions and deletions
    $addShadeColors = @{
        100 = @{ bg = "rgba(152, 255, 152, 0.15)"; color = "rgb(152 255 152)" }
        200 = @{ bg = "rgba(0, 255, 127, 0.15)"; color = "rgb(0 255 127)" }
        300 = @{ bg = "rgba(50, 205, 50, 0.15)"; color = "rgb(50 205 50)" }
        400 = @{ bg = "rgba(32, 178, 170, 0.15)"; color = "rgb(32 178 170)" }
        500 = @{ bg = "rgba(0, 178, 210, 0.15)"; color = "rgb(0 178 210)" }
        600 = @{ bg = "rgba(0, 133, 122, 0.15)"; color = "rgb(0 133 122)" }
        700 = @{ bg = "rgba(0, 255, 0, 0.15)"; color = "rgb(0 255 0)" }
        800 = @{ bg = "rgba(0, 92, 0, 0.15)"; color = "rgb(0 255 127)" }
        900 = @{ bg = "rgba(0, 50, 0, 0.15)"; color = "rgb(0 255 127)" }
    }

    $delShadeColors = @{
        100 = @{ bg = "rgba(255, 111, 156, 0.15)"; color = "rgb(255 111 156)" }
        200 = @{ bg = "rgba(255, 75, 156, 0.15)"; color = "rgb(255 75 156)" }
        300 = @{ bg = "rgba(255, 20, 147, 0.15)"; color = "rgb(255 20 147)" }
        400 = @{ bg = "rgba(224, 110, 146, 0.15)"; color = "rgb(224 110 146)" }
        500 = @{ bg = "rgba(213, 0, 109, 0.15)"; color = "rgb(213 0 109)" }
        600 = @{ bg = "rgba(215, 61, 133, 0.15)"; color = "rgb(215 61 133)" }
        700 = @{ bg = "rgba(192, 58, 105, 0.15)"; color = "rgb(192 58 105)" }
        800 = @{ bg = "rgba(191, 0, 72, 0.15)"; color = "rgb(191 0 72)" }
        900 = @{ bg = "rgba(155, 0, 67, 0.15)"; color = "rgb(255 105 180)" }
    }

    return @{
        Add = $addShadeColors
        Del = $delShadeColors
    }
}

function Get-ShadeCss {
    $shadeColors = Get-ShadeColorDefinitions
    $css = @"

        /* Shade-based colors for additions using success spectrum */
"@

    # Generate CSS for addition shades
    foreach ($shade in $shadeColors.Add.Keys | Sort-Object) {
        $colors = $shadeColors.Add[$shade]
        $css += @"
        .diff-line.diff-add.shade-$shade {
            background: $($colors.bg);
            color: $($colors.color);
            border-left: 2px solid $($colors.color);
        }
"@
    }

    $css += @"

        /* Shade-based colors for deletions using error spectrum */
"@

    # Generate CSS for deletion shades
    foreach ($shade in $shadeColors.Del.Keys | Sort-Object) {
        $colors = $shadeColors.Del[$shade]
        $css += @"
        .diff-line.diff-del.shade-$shade {
            background: $($colors.bg);
            color: $($colors.color);
            border-left: 2px solid $($colors.color);
        }
"@
    }

    return $css
}

function Export-HtmlReport {
    param(
        [array]$Evolution,
        [string]$OutputDir,
        [bool]$NoComponentFiltering = $false
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
        /* Radio group button styles */
        .view-buttons { display: inline-flex; gap: 4px; }
        .toggle-btn {
            background: rgb(0 17 34);
            color: rgb(136 255 255);
            border: 1px solid rgb(0 63 103);
            padding: 6px 12px;
            border-radius: 3px;
            cursor: pointer;
            font-size: 11px;
            transition: all 0.2s ease;
        } /*##NeonSurge --bg-surface --text-muted --border-subtle */
        .toggle-btn:hover:not(.active) {
            background: rgb(25 25 112);
            border-color: rgb(13 92 255);
            color: rgb(255 255 255);
        } /*##NeonSurge --bg-elevated --border-default */

        /* Active states for each button type */
        .toggle-btn.active {
            cursor: default;
            font-weight: bold;
        }
        .toggle-btn.code-btn.active {
            background: rgb(255 204 0);
            color: rgb(0 0 0);
            border-color: rgb(255 204 0);
        } /*##NeonSurge --accent-500 Electric Yellow */
        .toggle-btn.diff-btn.active {
            background: rgb(0 255 255);
            color: rgb(0 0 0);
            border-color: rgb(0 255 255);
        } /*##NeonSurge --secondary-300 Electric Cyan */
        .toggle-btn.compressed-btn.active {
            background: rgb(255 20 147);
            color: rgb(255 255 255);
            border-color: rgb(255 20 147);
        } /*##NeonSurge --primary-500 Electric Pink */
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
        .compressed-header {
            background: rgb(13 13 42); /*##NeonSurge --bg-secondary */
            color: rgb(0 255 255); /*##NeonSurge --text-secondary */
            font-weight: bold;
            padding: 2px 12px;
            margin: 0; /* Remove spacing between headers */
            border-left: 3px solid rgb(255 20 147);
            font-size: 12px;
        }

        /* Base compressed diff line styles - fixed spacing */
        .compressed-content .diff-line {
            display: block;
            margin: 0;
            padding: 0 8px;
            line-height: 1.2;  /* Tight line height to prevent double spacing */
            font-family: 'Consolas', monospace;
            white-space: pre;
        }

        .compressed-content .diff-line.unchanged {
            color: rgb(255 255 255); /*##NeonSurge --text-primary */
            opacity: 0.7;
        }

        /* Line number styling */
        .compressed-content .line-num,
        .compressed-content .line-num-unchanged {
            display: inline-block;
            width: 45px;
            text-align: right;
            margin-right: 8px;
            color: rgb(74 150 255);
            opacity: 0.6;
            font-size: 11px;
        }

        .compressed-content .diff-line.diff-add .line-num,
        .compressed-content .diff-line.diff-del .line-num {
            opacity: 1;
            font-weight: bold;
        }

        /* Hover styles with electric yellow highlight */
        .compressed-content .diff-line:hover {
            background: rgba(255, 204, 0, 0.2) !important; /* Electric yellow with transparency */
            border-left: 3px solid rgb(255 204 0); /* Solid electric yellow border */
            padding-left: 7px; /* Adjust padding to compensate for border */
            cursor: pointer;
            transition: all 0.15s ease;
        }

        .compressed-content .diff-line:hover .line-num,
        .compressed-content .diff-line:hover .line-num-unchanged {
            color: rgb(255 204 0); /* Electric yellow for line numbers on hover */
            font-weight: bold;
        }

        /* Component-specific commits styling */
        .component-specific {
            background: rgba(0, 255, 127, 0.1);
            border-left: 4px solid rgb(0 255 127);
            margin: 15px;
            padding: 15px;
            border-radius: 4px;
        }
        .component-specific h5 {
            color: rgb(0 255 127);
            margin: 0 0 10px 0;
            font-size: 1.1em;
        }

        /* Custom tooltips with electric yellow theme */
        [data-tooltip] {
            position: relative;
            cursor: help;
        }
        [data-tooltip]:hover::before {
            content: attr(data-tooltip);
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%) translateY(-8px);
            background: rgb(255 204 0); /* Electric yellow */
            color: rgb(0 0 0);
            padding: 6px 10px;
            border-radius: 3px;
            white-space: nowrap;
            z-index: 1000;
            font-size: 12px;
            font-weight: normal;
            box-shadow: 0 2px 8px rgba(0,0,0,0.3);
        }
        [data-tooltip]:hover::after {
            content: '';
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            border: 5px solid transparent;
            border-top-color: rgb(255 204 0);
            margin-bottom: -2px;
        }

$(Get-ShadeCss)
    </style>
    <script>
        function setViewMode(btn, mode, versionId) {
            // Find the parent version container
            const versionContainer = document.getElementById('version_' + versionId);
            if (!versionContainer) return;

            // Find all buttons in this version's button group
            const buttonContainer = versionContainer.querySelector('.view-buttons');
            const buttons = buttonContainer.querySelectorAll('.toggle-btn');

            // Remove active class from all buttons
            buttons.forEach(b => b.classList.remove('active'));

            // Add active class to clicked button
            btn.classList.add('active');

            // Hide all content areas
            const codeContent = versionContainer.querySelector('.code-content');
            const diffContainer = versionContainer.querySelector('.diff-container');

            // Compressed content has a specific ID pattern
            const chainIndex = versionId.split('_')[0];
            const compressedContent = document.getElementById('compressed_' + chainIndex);

            if (codeContent) codeContent.classList.add('collapsed');
            if (diffContainer) diffContainer.classList.remove('active');
            if (compressedContent) compressedContent.classList.add('collapsed');

            // Show the selected content
            if (mode === 'code' && codeContent) {
                codeContent.classList.remove('collapsed');
                addCopyButton(codeContent);
            } else if (mode === 'diff' && diffContainer) {
                // Generate diff if needed
                const currentId = btn.getAttribute('data-current');
                const previousId = btn.getAttribute('data-previous');
                const currentTitle = btn.getAttribute('data-current-title');
                const prevTitle = btn.getAttribute('data-prev-title');
                const diffId = btn.getAttribute('data-diff-id');

                if (currentId && previousId && diffId) {
                    showDiff(currentId, previousId, currentTitle, prevTitle, diffId);
                }

                diffContainer.classList.add('active');
                // Add a single copy button for the unified diff if not already present
                if (!diffContainer.querySelector('.copy-btn')) {
                    const copyBtn = document.createElement('button');
                    copyBtn.className = 'copy-btn';
                    copyBtn.textContent = 'Copy Unified Diff';
                    copyBtn.style.position = 'absolute';
                    copyBtn.style.top = '10px';
                    copyBtn.style.right = '10px';
                    copyBtn.style.zIndex = '100';
                    copyBtn.onclick = function() {
                        copyUnifiedDiff(diffContainer, btn.getAttribute('data-current-title'), btn.getAttribute('data-prev-title'));
                    };
                    diffContainer.appendChild(copyBtn);
                }
            } else if (mode === 'compressed' && compressedContent) {
                compressedContent.classList.remove('collapsed');
                addCopyButton(compressedContent);
            }
        }

        // Legacy function for backward compatibility
        function toggleCode(btn, targetId) {
            const content = document.getElementById(targetId);
            if (content.classList.contains('collapsed')) {
                content.classList.remove('collapsed');
                btn.textContent = 'Hide';
                addCopyButton(content);
            } else {
                content.classList.add('collapsed');
                btn.textContent = 'Show';
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

        function copyUnifiedDiff(diffContainer, currentTitle, prevTitle) {
            const copyBtn = diffContainer.querySelector('.copy-btn');
            const originalText = copyBtn.textContent;

            // Get the left (previous) and right (current) content
            const leftPanel = diffContainer.querySelector('.diff-left .diff-content');
            const rightPanel = diffContainer.querySelector('.diff-side:last-child .diff-content');

            if (!leftPanel || !rightPanel) return;

            // Build unified diff format
            let unifiedDiff = '--- ' + prevTitle + '\n';
            unifiedDiff += '+++ ' + currentTitle + '\n';
            unifiedDiff += '@@ Changes @@\n';

            // Get all diff lines
            const leftLines = leftPanel.querySelectorAll('.diff-line');
            const rightLines = rightPanel.querySelectorAll('.diff-line');

            // Process lines to create unified diff
            leftLines.forEach((line, index) => {
                if (line.classList.contains('diff-removed')) {
                    const content = line.querySelector('.diff-line-content');
                    if (content) {
                        unifiedDiff += '-' + content.innerText + '\n';
                    }
                } else if (line.classList.contains('diff-modified')) {
                    const content = line.querySelector('.diff-line-content');
                    if (content) {
                        unifiedDiff += '-' + content.innerText + '\n';
                    }
                }
            });

            rightLines.forEach((line, index) => {
                if (line.classList.contains('diff-added')) {
                    const content = line.querySelector('.diff-line-content');
                    if (content) {
                        unifiedDiff += '+' + content.innerText + '\n';
                    }
                } else if (line.classList.contains('diff-modified')) {
                    const content = line.querySelector('.diff-line-content');
                    if (content) {
                        unifiedDiff += '+' + content.innerText + '\n';
                    }
                } else if (line.classList.contains('diff-unchanged')) {
                    const content = line.querySelector('.diff-line-content');
                    if (content) {
                        unifiedDiff += ' ' + content.innerText + '\n';
                    }
                }
            });

            navigator.clipboard.writeText(unifiedDiff).then(() => {
                copyBtn.textContent = '✓ Copied!';
                copyBtn.classList.add('copied');
                setTimeout(() => {
                    copyBtn.textContent = originalText;
                    copyBtn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy:', err);
            });
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

        function showDiffFromCompressed(diffId) {
            // Find the diff button with matching data-diff-id
            const diffBtn = document.querySelector('[data-diff-id="' + diffId + '"]');
            if (diffBtn) {
                // Click the diff button to show the diff
                diffBtn.click();
                // Scroll to the diff container
                const diffContainer = document.getElementById(diffId);
                if (diffContainer) {
                    diffContainer.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }
            }
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
            
            # Create unique version container ID
            $versionContainerId = "${chainIndex}_${versionIndex}"

            $html += @"
            <div class="version" id="version_$versionContainerId">
                <div class="version-header">
                    <div class="version-info">
                        <span class="version-date">$($version.Date.ToString('yyyy-MM-dd HH:mm'))</span>
                        by $($version.Author) |
                        Commit: $($version.Commit.Substring(0,8)) |
                        Lines: $($version.StartLine)-$($version.EndLine) ($($version.LineCount) lines)
                    </div>
                    <div class="view-buttons">
                        <button class="toggle-btn code-btn" onclick="setViewMode(this, 'code', '$versionContainerId')">Code</button>
"@

            # Add diff button for versions that have a previous version
            # Since versions are stored in descending order (newest first),
            # the "previous" version in time is at index+1, not index-1
            if ($versionIndex -lt $chain.Versions.Count - 1) {
                $prevCodeId = "code_$chainIndex`_$($versionIndex+1)"
                $prevVersion = $chain.Versions[$versionIndex+1]
                $currentTitle = "Current ($($version.Date.ToString('MM-dd HH:mm')))"
                $prevTitle = "Previous ($($prevVersion.Date.ToString('MM-dd HH:mm')))"

                $html += @"
                        <button class="toggle-btn diff-btn"
                            onclick="setViewMode(this, 'diff', '$versionContainerId')"
                            data-current="$codeId"
                            data-previous="$prevCodeId"
                            data-current-title="$currentTitle"
                            data-prev-title="$prevTitle"
                            data-diff-id="$diffId">Diff</button>
"@
            }
            # Add compressed diff button for the last (oldest) version
            elseif ($versionIndex -eq $chain.Versions.Count - 1 -and $chain.Versions.Count -gt 1) {
                $compressedDiffId = "compressed_$chainIndex"
                $html += @"
                        <button class="toggle-btn compressed-btn" onclick="setViewMode(this, 'compressed', '$versionContainerId')">Compressed</button>
"@
            }

            $html += @"
                    </div>
                </div>
"@

            # Automatically show enhanced commit information when structured data is detected (unless SimpleCommitDisplay is set)
            if (-not $SimpleCommitDisplay -and $chain.ParsedCommits) {
                # Find the parsed commit for this version
                $parsedCommit = $chain.ParsedCommits | Where-Object { $_.CommitHash -eq $version.Commit } | Select-Object -First 1

                # Show enhanced view only if structured data was found
                if ($parsedCommit -and $parsedCommit.IsStructured) {
                    $html += @"
                <div style="margin: 10px 0; padding: 10px; border-left: 3px solid #00ffff;">
"@
                    if ($parsedCommit.ConventionalType) {
                        $scopeText = if ($parsedCommit.Scope) { "($($parsedCommit.Scope))" } else { "" }
                        $html += @"
                    <div style="color: #ff14ff; font-weight: bold;">$($parsedCommit.ConventionalType)${scopeText}: $($parsedCommit.Summary)</div>
"@
                    }

                    if ($parsedCommit.Components.Count -gt 0) {
                        $html += @"
                    <div style="margin-top: 5px;">
"@
                        foreach ($component in $parsedCommit.Components) {
                            $fromNotesText = if ($component.FromNotes) { " (from git notes)" } else { "" }
                            $actionColor = switch ($component.Action) {
                                "NEW" { "#00ff00" }
                                "MODIFIED" { "#00ffff" }
                                "REMOVED" { "#ff1493" }
                                default { "#ffcc00" }
                            }
                            $html += @"
                        <div style="margin-left: 20px;">
                            <span style="color: $actionColor;">[$($component.Name)] $($component.Action):</span>
                            <span style="color: #ffffff;">$($component.Description)$fromNotesText</span>
                        </div>
"@
                        }
                        $html += @"
                    </div>
"@
                    }
                    $html += @"
                </div>
"@
                } else {
                    # Show regular commit message
                    $html += @"
                <div><em>$($version.Message)</em></div>
"@
                }
            } else {
                # Show regular commit message
                $html += @"
                <div><em>$($version.Message)</em></div>
"@
            }

            $html += @"
                <div class="code-content collapsed" id="$codeId">$escapedContent</div>
"@

            # Add compressed diff content for the last (oldest) version
            if ($versionIndex -eq $chain.Versions.Count - 1 -and $chain.Versions.Count -gt 1) {
                $compressedDiffId = "compressed_$chainIndex"
                $compressedDiffContent = Get-CompressedDiff -Chain $chain -ChainIndex $chainIndex
                
                $html += @"
                <div class="code-content collapsed" id="$compressedDiffId">$compressedDiffContent</div>
"@
            }

            # Add diff container
            if ($versionIndex -lt $chain.Versions.Count - 1) {
                $html += @"
                <div class="diff-container" id="$diffId"></div>
"@
            }
            
            $html += "</div>"
            $versionIndex++
        }
        
        # Show component-specific commits first if they exist (unless filtering is disabled)
        if (-not $NoComponentFiltering -and $chain.ComponentCommits -and $chain.ComponentCommits.Count -gt 0) {
            $html += @"
            <div class="component-specific" style="background: rgba(0, 255, 127, 0.1); border-left: 4px solid rgb(0 255 127); margin: 15px; padding: 15px; border-radius: 4px;">
                <h5 style="color: rgb(0 255 127); margin: 0 0 10px 0; font-size: 1.1em;">✓ Component-Specific Changes for $($chain.Name)</h5>
"@
            foreach ($commit in $chain.ComponentCommits) {
                foreach ($component in $commit.RelevantComponents) {
                    $actionColor = switch ($component.Action) {
                        "NEW" { "#00ff00" }
                        "MODIFIED" { "#ffcc00" }
                        "REMOVED" { "#ff1493" }
                        "RENAMED" { "#00ffff" }
                        "MOVED" { "#ff14ff" }
                        default { "#ffffff" }
                    }
                    $fromNotesText = if ($component.FromNotes) { " (from git notes)" } else { "" }
                    $html += @"
                <div style="margin: 8px 0; padding-left: 20px;">
                    <span style="color: $actionColor; font-weight: bold;">$($component.Action):</span>
                    <span style="color: #ffffff;">$($component.Description)</span>
                    <span style="color: #808080; font-size: 0.85em;">$fromNotesText</span>
                </div>
"@
                }
            }
            $html += @"
            </div>
"@
        }

        # Automatically show commit groups when structured commits are detected (unless SimpleCommitDisplay is set)
        if (-not $SimpleCommitDisplay -and $chain.CommitGroups -and $chain.CommitGroups.Count -gt 0) {
            # Only show groups if we have meaningful structured data
            $hasStructuredData = $chain.ParsedCommits | Where-Object { $_.IsStructured -or $_.ConventionalType -or $_.SemanticInfo.ActionType } | Select-Object -First 1
            if ($hasStructuredData) {

            # Determine header text based on whether we showed component commits
            $headerText = if (-not $NoComponentFiltering -and $chain.ComponentCommits -and $chain.ComponentCommits.Count -gt 0) {
                "Other Commit Groups"
            } else {
                "Commit Groups"
            }

            $html += @"
            <div class="changes-summary" style="background: #1a1a1a; border: 1px solid #00ffff; margin-top: 20px;">
                <h4 style="color: #ff14ff;">$headerText</h4>
"@
            foreach ($group in $chain.CommitGroups) {
                $groupColor = switch ($group.Type) {
                    'component' { "#00ffff" }
                    'conventional' { "#ff14ff" }
                    'semantic' { "#ffcc00" }
                    default { "#ffffff" }
                }

                $html += @"
                <div style="margin: 10px 0; padding: 10px; border-left: 3px solid $groupColor;">
                    <div style="color: $groupColor; font-weight: bold;">$($group.Summary)</div>
"@

                if ($group.Type -eq 'component' -and $group.Descriptions) {
                    $html += @"
                    <div style="margin-top: 5px; margin-left: 20px; color: #ffffff;">
"@
                    foreach ($desc in ($group.Descriptions | Select-Object -First 3)) {
                        $html += @"
                        <div>• $desc</div>
"@
                    }
                    if ($group.Descriptions.Count -gt 3) {
                        $html += @"
                        <div style="color: #808080;">... and $($group.Descriptions.Count - 3) more</div>
"@
                    }
                    $html += @"
                    </div>
"@
                }

                $html += @"
                </div>
"@
            }
            $html += @"
            </div>
"@
            }
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
        $commitIndex++  # Increment for next commit pair
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
        $commitIndex++  # Increment for next commit pair
    }
    
    return $diff -join "`n"
}

function Cleanup-TempFiles {
    param([string]$OutputDir)
    
    # Remove temporary JavaScript files
    Get-ChildItem $OutputDir -Filter "*.js" | Where-Object { $_.Name -match "_[a-f0-9]{8}\.js$" } | Remove-Item -Force
}

function Main {
    Write-Host "Code Evolution Tracker" -ForegroundColor Cyan
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
    if ($VerbosePreference -eq 'Continue' -and $fileVersions.Count -gt 0) {
        Write-Verbose "Version summary by file:"
        $fileVersions | Group-Object { $_.File } | ForEach-Object {
            Write-Verbose "  $($_.Name): $($_.Count) versions"
        }
    }
        
        # Step 2: Parse with Acorn
        Write-Host "`nStep 2: Parsing code with language auto-detection..." -ForegroundColor Yellow
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
            Export-HtmlReport -Evolution $evolution -OutputDir $OutputDir -NoComponentFiltering $NoComponentFiltering
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