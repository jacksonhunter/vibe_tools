# Code Evolution Tracker

A powerful PowerShell tool that tracks how code evolves through Git history, extracting individual code elements (functions, classes, constants) and showing their specific changes across commits.

## Features

- **Multi-Language Support**: JavaScript, TypeScript, Python, Bash, PowerShell, R
- **AST-Based Parsing**: Uses tree-sitter for accurate code extraction (not regex)
- **Component-Level Tracking**: Tracks individual functions, classes, methods, and constants
- **Automatic Commit Enhancement**: Detects and displays structured commit messages
- **Multiple Output Formats**:
  - Interactive HTML report with NeonSurge theme
  - Unified diff format
  - Compressed diff format (reduces 80K+ lines to ~5K)
- **Git Notes Integration**: Supports retroactive documentation

## Installation

### Prerequisites
- Git repository
- PowerShell (Windows PowerShell or PowerShell Core)
- Node.js (for parser dependencies)

### Setup
```bash
# Clone the repository
git clone <repository-url>
cd vibe_tools/code_evolver

# Dependencies are auto-installed on first run
```

## Usage

### Basic Examples

```powershell
# Track a specific function's evolution
.\Track-CodeEvolution.ps1 -FunctionName "handleRequest" -ExportHtml

# Track all classes extending a base class
.\Track-CodeEvolution.ps1 -BaseClass "BaseService" -ShowDiffs

# Track a specific file's evolution
.\Track-CodeEvolution.ps1 -FilePath "src/utils.js" -ExportHtml

# Track a specific class
.\Track-CodeEvolution.ps1 -ClassName "UserService" -ExportCompressedDiff
```

### Parameters

- `-BaseClass <string>`: Track classes extending a specific base class
- `-ClassName <string>`: Track a specific class
- `-FunctionName <string>`: Track a specific function or method
- `-Globals`: Track global variable assignments
- `-Exports`: Track module exports
- `-FilePath <string>`: Filter to specific file(s), supports wildcards
- `-ShowDiffs`: Display diffs in console
- `-ExportHtml`: Generate interactive HTML report
- `-ExportUnifiedDiff`: Export traditional unified diff
- `-ExportCompressedDiff`: Export compressed diff format
- `-SimpleCommitDisplay`: Disable automatic commit enhancement
- `-Verbose`: Show detailed progress

### Output Files

Reports are saved to `./code-evolution-analysis/`:
- `evolution-report.html` - Interactive visual report
- `evolution-unified-diff.txt` - Traditional chronological diffs
- `evolution-compressed-diff.txt` - Inline changes with final code
- `evolution-timeline.json` - Raw evolution data

## Commit Message Format

The tool automatically detects and enhances structured commit messages:

```
feat(filename): Summary under 50 chars

[FunctionName] NEW: Added validation logic
[ClassName] MODIFIED: Updated error handling
[ConstantName] REMOVED: Deprecated constant
```

**Actions**: NEW, MODIFIED, REMOVED, RENAMED, MOVED

### Adding Git Notes

Enhance existing commits with structured documentation:

```bash
git notes add -m "[UserValidator] MODIFIED: Enhanced email validation
[UserService] MODIFIED: Updated validation logic" <commit-hash>
```

## Compressed Diff Format

The compressed diff format shows all historical changes inline with the final code:

```
@@@ commit1 → commit2 @@@
Author: name | Date | Message

L52: - old code that was removed
L52: + new code that replaced it
52  final version of the line
```

This reduces file size by ~95% while preserving all change information.

## Language Support

### Fully Supported
- **JavaScript/TypeScript** (.js, .jsx, .ts, .tsx, .mjs, .cjs)
- **Python** (.py, .pyw)
- **Bash** (.sh, .bash)
- **PowerShell** (.ps1, .psm1, .psd1)
- **R** (.r, .R) - Including R6, S3, S4 classes

### Parser Details
- Uses web-tree-sitter WASM parsers (language version 15)
- Fallback to Acorn for JavaScript if WASM fails
- All grammars compiled with tree-sitter CLI 0.25.x

## Visual Features

### NeonSurge Theme
- High-contrast cyberpunk aesthetic
- Color-coded changes:
  - Green: Additions
  - Pink: Deletions
  - Yellow: Modifications
  - Cyan: Component groups

### Radio Group View Buttons
- **Code**: Show final version
- **Diff**: Side-by-side comparison
- **Compressed**: Inline historical changes

## Advanced Features

### Component Tracking
Tracks specific code elements:
- Functions and arrow functions
- Classes and inheritance
- Methods (instance and static)
- Constants (top-level only)
- Global assignments (window.*, global.*)
- Module exports

### Commit Grouping
Automatically groups related commits:
- By component and action
- By conventional commit type
- By semantic patterns

## Troubleshooting

### No files found
- Ensure you're in a Git repository
- Check file path patterns
- Verify files exist in Git history

### Parser errors
- Node.js must be installed
- WASM files are in `grammars/` directory
- Check language is supported

### Performance
- Large repositories may take time
- Use `-FilePath` to filter
- Compressed diff reduces output size

## Contributing

See [CLAUDE.md](../CLAUDE.md) for development guidelines and commit message format.

## License

Part of the vibe_tools suite - See parent repository for license information.