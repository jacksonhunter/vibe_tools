# Code Evolver 📊

Track and visualize code evolution through Git history using AST parsing.

## Features

- **Accurate Code Extraction**: Uses Acorn AST parser, not regex
- **Git Integration**: Analyzes complete version history
- **Multiple Export Formats**:
  - HTML with interactive diffs
  - Unified diff for analysis
  - Compressed diff showing all changes inline
- **High Contrast Theme**: Neon Surge color scheme for readability

## Requirements

- PowerShell 5.0+
- Node.js 14+
- Git
- npm (for Acorn dependencies)

## Installation

```bash
# Install Node dependencies (first time only)
npm init -y
npm install acorn acorn-walk
```

## Usage

### Track a specific class
```powershell
.\Track-CodeEvolution-Final.ps1 -ClassName "UserService" -ExportHtml
```

### Track classes extending a base class
```powershell
.\Track-CodeEvolution-Final.ps1 -BaseClass "BaseService" -ShowDiffs
```

### Export all formats
```powershell
.\Track-CodeEvolution-Final.ps1 -ClassName "MyClass" -ExportHtml -ExportUnifiedDiff -ExportCompressedDiff
```

## Parameters

- `-BaseClass [string]`: Track classes extending this base class
- `-ClassName [string]`: Track a specific class name
- `-FilePath [string]`: Analyze a specific file
- `-OutputDir [string]`: Output directory (default: ./code-evolution-analysis)
- `-ShowDiffs`: Display diffs in console
- `-ExportHtml`: Generate interactive HTML report
- `-ExportUnifiedDiff`: Generate unified diff text file
- `-ExportCompressedDiff`: Generate compressed diff with all changes inline
- `-Verbose`: Show detailed progress

## Output

Reports are saved to `./code-evolution-analysis/`:
- `evolution-report.html` - Interactive HTML report
- `evolution-unified-diff.txt` - Chronological unified diffs
- `evolution-compressed-diff.txt` - All changes shown inline
- `evolution-timeline.json` - Raw evolution data

## Color Scheme

Using Neon Surge theme for high contrast:
- **Additions**: Bright green (`rgb(0 255 127)`)
- **Deletions**: Electric pink (`rgb(255 20 147)`)
- **Modifications**: Electric yellow (`rgb(255 204 0)`)
- **Background**: Pure black for maximum contrast

## Examples

### Analyze a React component
```powershell
.\Track-CodeEvolution-Final.ps1 -ClassName "UserProfile" -FilePath "src/components/UserProfile.jsx" -ExportHtml
```

### Track all service classes
```powershell
.\Track-CodeEvolution-Final.ps1 -BaseClass "BaseService" -ExportHtml -ExportCompressedDiff
```

## Tips

- Use `-ExportCompressedDiff` to see all historical changes in one view
- The HTML report includes interactive side-by-side diffs
- Use `-Verbose` to troubleshoot parsing issues

## License

MIT