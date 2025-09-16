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
- Git repository (your project must be a git repo)
- PowerShell 5.1+ (Windows PowerShell or PowerShell Core)
- Node.js 14+ (for parser dependencies)

### Setup (Without Adding Files to Your Project)

#### Option 1: External Tool Installation (Recommended)
```bash
# 1. Clone vibe_tools OUTSIDE your project
git clone https://github.com/yourusername/vibe_tools.git ~/tools/vibe_tools

# 2. In YOUR project, add to .gitignore:
echo "code-evolution-analysis/" >> .gitignore

# 3. Run from your project root:
powershell.exe -ExecutionPolicy Bypass -File "~/tools/vibe_tools/code_evolver/Track-CodeEvolution.ps1" -ClassName "YourClass" -ExportHtml
```

#### Option 2: PowerShell Alias (Most Convenient)
```powershell
# Add to your PowerShell profile ($PROFILE):
Set-Alias track "C:\tools\vibe_tools\code_evolver\Track-CodeEvolution.ps1"

# Then from any project:
track -ClassName "MyClass" -ExportHtml
```

#### Option 3: Temporary Analysis
```bash
# Clone to temp location
git clone https://github.com/yourusername/vibe_tools.git /tmp/vibe_tools

# Run and clean up
powershell /tmp/vibe_tools/code_evolver/Track-CodeEvolution.ps1 -ClassName "MyClass" -ExportHtml
rm -rf ./code-evolution-analysis  # Remove after viewing
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
@@@ a4da2cf → 2e3e6da @@@ + added − deleted
@@@ 2e3e6da → 709a707 @@@ + added − deleted

L2: + static _ = this.register;
L2: - static priority = 5; // Runs after routing
2: = static priority = 5;
```

### Format Features
- **Headers**: Show commit progression with clickable colored indicators
- **Line-level changes**: `L{num}:` prefix for changes, plain number for final state
- **Operations**: `+` (added), `-` (deleted), `=` (final version)
- **Shade coding**: Each commit gets a unique color shade (100-900 scale)
- **Size reduction**: ~75% smaller than traditional diffs
- **Machine readable**: Consistent pattern for LLM parsing

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

## Recent Updates (September 2025)

### Interactive Features
- **Clickable diff lines**: Click any change in compressed view to jump to its diff
- **Unified diff copy**: Single button exports proper unified diff format
- **Shade-colored headers**: Commit indicators match their diff colors
- **Radio button views**: Exclusive Code/Diff/Compressed view switching

### Bug Fixes
- **Fixed diff ordering**: Now shows older → newer (chronological)
- **Line number accuracy**: Removed blank line ignoring for accurate line numbers
- **Centralized colors**: Single source of truth for shade definitions
- **Version indexing**: Fixed reversed version ordering in diff display

### Parser Improvements
- **R language**: Full support for R6, S3, S4 classes and methods
- **PowerShell**: Complete AST support via Airbus-CERT grammar
- **Tree-sitter 0.25.x**: All grammars updated to latest versions
- **Auto language detection**: Parser automatically detects file language

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

### Windows-specific issues
- Use forward slashes in paths or escape backslashes
- PowerShell execution policy may need `-ExecutionPolicy Bypass`
- BOM issues are handled automatically

## Contributing

See [CLAUDE.md](../CLAUDE.md) for development guidelines and commit message format.

## License

Part of the vibe_tools suite - See parent repository for license information.