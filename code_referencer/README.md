# Code Referencer

A cross-reference analysis tool that finds all references to symbols defined in a source file across your codebase.

## Features

- **Symbol Extraction**: Automatically extracts classes, functions, methods, globals, and constants from source files
- **Reference Detection**: Finds all usages of those symbols across your project
- **Context-Aware**: Shows which function/method contains each reference
- **Usage Classification**: Identifies whether references are calls, instantiations, imports, or inheritance
- **Multi-Language Support**: Works with JavaScript, TypeScript, Python, PowerShell, Bash, R, and C#
- **AST-Based**: Uses tree-sitter for accurate parsing, not regex matching

## Installation

### Method 1: Global Installation
Install once, use anywhere on your system:

```powershell
# Install with PATH integration
.\Install-GlobalTool.ps1 -AddToPath -CreateAlias

# Then from any project:
find-references -FilePath MyClass.js -ProjectPath .
```

### Method 2: Export to Project
Copy the tool to a specific project:

```powershell
# Export to another project
.\Export-ToProject.ps1 -TargetProject "C:\MyProject" -CreateGitIgnore

# Then from that project:
.\.tools\code-referencer\run.ps1 -FilePath src\MyClass.py
```

### Method 3: Direct Usage
Run directly from this directory:

```powershell
.\Find-CodeReferences.ps1 -FilePath path\to\file.js -ProjectPath .
```

## Usage Examples

### Basic Usage
```powershell
# Find all references to symbols in UserService.js
.\Find-CodeReferences.ps1 -FilePath src\UserService.js
```

### Search Specific Directory
```powershell
# Limit search to src directory
.\Find-CodeReferences.ps1 -FilePath utils.js -ProjectPath .\src
```

### Include All Symbol Types
```powershell
# Include globals, exports, and constants
.\Find-CodeReferences.ps1 -FilePath app.js -IncludeGlobals -IncludeExports -IncludeConstants
```

### Export Results
```powershell
# Export to JSON
.\Find-CodeReferences.ps1 -FilePath lib\database.py -OutputFormat json -ExportJson

# Future: Export to HTML
.\Find-CodeReferences.ps1 -FilePath MyClass.cs -ExportHtml
```

## Output Example

```
FUNCTION: validateEmail
  References: 7
  src/auth.js
    Line 11: call (in login)
    Line 25: call (in register)
  src/utils.js
    Line 45: call

CLASS: UserService
  References: 5
  src/index.js
    Line 3: import
    Line 7: instantiation (in main)
  tests/user.test.js
    Line 40: instantiation (in setupTests)

Summary:
  Total symbols: 6
  Total references: 14
  Unused symbols: 2
```

## Requirements

- Node.js (for the parser)
- PowerShell 5.1+ or PowerShell Core
- Git repository (optional, but recommended for better file discovery)

## Supported Languages

- JavaScript (.js, .jsx, .mjs, .cjs)
- TypeScript (.ts, .tsx)
- Python (.py)
- PowerShell (.ps1, .psm1, .psd1)
- Bash (.sh, .bash)
- R (.r, .R)
- C# (.cs, .csx)

## How It Works

1. **Extraction Phase**: Parses the target file using tree-sitter to extract all defined symbols
2. **Search Phase**: Scans all same-language files in the project directory
3. **Detection Phase**: Uses AST analysis to find genuine references (not just text matches)
4. **Reporting Phase**: Aggregates and displays results with context information

## Performance

- Efficient AST-based parsing (single parse per file)
- Filters to only same-language files
- Progress indicator for large projects
- Typical performance: ~100 files/second

## Troubleshooting

### "Parser not found"
Run `npm install` in the code_referencer directory to install web-tree-sitter.

### "No symbols found"
- Check that the file contains valid code in a supported language
- Try including more symbol types with `-IncludeGlobals`, `-IncludeExports`, etc.

### Slow performance
- Limit the search scope with a specific `-ProjectPath`
- Exclude node_modules and other large directories

## Integration with Code Evolver

This tool complements the Code Evolver by providing reference analysis for symbols. While Code Evolver tracks how code changes over time, Code Referencer shows how code is used across your project.

## License

Same as vibe_tools project