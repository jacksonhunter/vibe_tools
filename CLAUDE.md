# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🛠️ Vibe Tools - Code Evolution Tracker

A tool for tracking how JavaScript/TypeScript code evolves over time through Git history, extracting individual code elements (functions, classes, constants) and showing their specific changes across commits.

Originally developed as part of the vibe-reader-extension project, now evolving as an independent tool suite.

## Commit Message Format

When writing Git commits for this project, use component-specific annotations.

FORMAT:
<type>(<file/module>): <summary max 50 chars>

[ComponentName] ACTION: what changed
[NextComponent] ACTION: what changed

ACTIONS: NEW, MODIFIED, REMOVED, RENAMED, MOVED
TYPES: feat, fix, refactor, perf, test, docs, style, chore

GUIDELINES:

List the ACTUAL function/class names that changed.

GOOD EXAMPLE:
fix(SubscriberMiddleware): Fix async initialization

[initializeSubscriber] MODIFIED: Added await for config load
[handleRequest] MODIFIED: Check ready state before processing
[IS_READY] NEW: State flag constant

BAD EXAMPLE:
fix(SubscriberMiddleware): Fix async initialization

[initialization logic] MODIFIED: Added async handling
[request handler] MODIFIED: Added state check

For pure CSS/HTML changes, don't force component notation:
style(evolution-report): Switch to NeonSurge theme

WHY THIS FORMAT:

This allows our evolution tracker to show what actually changed in each function/class, not just repeat the file-level message for every component. When the tracker analyzes commits, it can extract component-specific changes and show meaningful evolution history for each code element.

## Architecture

### Core Flow

1. **Track-CodeEvolution.ps1** iterates through Git history for matching files
2. For each commit, extracts file content at that point in time
3. Passes content to **tree-sitter-parser.js** for AST analysis using web-tree-sitter WASM
4. Parser returns structured segment data (classes, functions, methods, constants)
5. PowerShell groups segments by name to create evolution chains
6. Generates reports showing how each function/class changed over time

### Key Components

- **Track-CodeEvolution.ps1**: PowerShell orchestrator managing Git traversal and report generation
- **lib/parsers/tree-sitter-parser.js**: Universal parser with auto language detection via WASM
- **lib/parsers/javascript-parser.js**: Acorn-based fallback for JavaScript/TypeScript
- **Compressed Diff Format**: Human and machine-readable format showing all changes inline with final code

### Output Formats

Reports saved to `./code-evolution-analysis/`:

- `evolution-report.html` - Interactive HTML with side-by-side diffs (Neon Surge theme)
- `evolution-unified-diff.txt` - Traditional chronological unified diffs
- `evolution-compressed-diff.txt` - Optimized format for LLM analysis
- `evolution-timeline.json` - Raw evolution data

## Commit Message Format

Use component-specific annotations when committing changes:

```
<type>(<file/module>): <summary max 50 chars>

[ComponentName] ACTION: what changed
[NextComponent] ACTION: what changed
```

**Actions**: NEW, MODIFIED, REMOVED, RENAMED, MOVED
**Types**: feat, fix, refactor, perf, test, docs, style, chore

### Example

```
fix(SubscriberMiddleware): Fix async initialization

[initializeSubscriber] MODIFIED: Added await for config load
[handleRequest] MODIFIED: Check ready state before processing
[IS_READY] NEW: State flag constant
```

This format enables the evolution tracker to show specific changes per component rather than repeating file-level messages.

## Problem Solved

Git shows file-level diffs which can be overwhelming when tracking specific functions. This tool automatically extracts and tracks individual code elements through their evolution, making it easier to understand how specific components changed rather than entire files.

## Technical Notes

- Windows environment: Use `powershell.exe -ExecutionPolicy Bypass` for scripts
- Requires: Git repository, Node.js, PowerShell Core or Windows PowerShell
- Parser architecture supports extension to other languages via `lib/parsers/`
- Compressed diff innovation: Shows final code once with all historical changes marked inline at their line positions (e.g., "L52: - old code" followed by "L52: + new code")

### Important Windows/Unix Interoperability Notes

- **BOM (Byte Order Mark) Issue**: When PowerShell writes UTF-8 files, it adds a BOM by default which breaks JSON parsing in Node.js. Always use `New-Object System.Text.UTF8Encoding $false` to write without BOM when passing files between PowerShell and Node.js.
- **File Extension Preservation**: The parser uses file extensions to auto-detect language. Temp files must preserve original extensions (e.g., `.ps1`, `.py`, `.sh`, `.r`, `.R`) for correct language detection.
- **JSON Argument Passing**: Due to PowerShell quote escaping issues, complex JSON is passed via temp files using `@filename` syntax rather than command-line arguments.
- **R Grammar Field Names**: The R grammar uses `lhs`/`rhs` for binary operators instead of `left`/`right` used by other grammars.

### Parser Implementation Status (Updated September 2025)

- **JavaScript**: ✅ Full support via web-tree-sitter WASM (language version 15)
  - Built from tree-sitter/tree-sitter-javascript (latest)
  - Acorn fallback available if WASM fails
- **Python**: ✅ Full support via web-tree-sitter WASM (language version 15)
  - Built from tree-sitter/tree-sitter-python (latest)
- **Bash**: ✅ Full support via web-tree-sitter WASM (language version 15)
  - Built from tree-sitter/tree-sitter-bash (latest)
- **PowerShell**: ✅ Full support via web-tree-sitter WASM (language version 15)
  - Built from Airbus-CERT/tree-sitter-powershell
  - Successfully extracts functions, classes, and methods
- **R**: ✅ Full support via web-tree-sitter WASM (language version 15)
  - Built from r-lib/tree-sitter-r (latest)
  - Supports R6 classes (`R6::R6Class()`), S3 classes (`class() <-`), S4 classes (`setClass()`)
  - Extracts functions (`name <- function()`), methods (`setMethod()`, `UseMethod()`)
  - Detects constants (UPPER_CASE), global assignments (`<<-`, `assign()`)
  - Note: R AST uses `lhs`/`rhs` fields for binary operators

## Installation and Usage

### Using Code Evolver in Your Project (Without Adding Files)

1. **Clone to a separate location** outside your project:
   ```bash
   git clone https://github.com/yourusername/vibe_tools.git ~/tools/vibe_tools
   ```

2. **Add to .gitignore** in your project:
   ```
   # Code Evolution Analysis (generated)
   code-evolution-analysis/
   ```

3. **Run from your project root**:
   ```powershell
   # Windows PowerShell
   powershell.exe -ExecutionPolicy Bypass -File "~/tools/vibe_tools/code_evolver/Track-CodeEvolution.ps1" -ClassName "YourClass" -ExportHtml

   # Or create an alias in your PowerShell profile
   Set-Alias track-evolution "~/tools/vibe_tools/code_evolver/Track-CodeEvolution.ps1"
   ```

4. **Output goes to** `./code-evolution-analysis/` which is gitignored

### Recent Updates (September 2025)

#### Enhanced Commit Message Parsing (September 14, 2025)
- **Automatic Detection**: Script now automatically parses and enhances structured commit messages
- **No Configuration Required**: Works out-of-the-box without opt-in flags
- **Component-Level Tracking**: Detects [Component] ACTION format in commit messages
- **Git Notes Support**: Automatically retrieves and displays git notes for retroactive documentation
- **Grouped Summaries**: Groups similar commits by component, type, or semantic action
- **Backward Compatible**: Shows plain commits as before, enhanced view only for structured data
- **Opt-Out Available**: Use `-SimpleCommitDisplay` flag to disable enhancements if needed

#### Radio Group View Buttons (September 14, 2025)
The HTML report now features radio-style view switching:
- **Code**, **Diff**, and **Compressed** buttons act as a radio group
- Only one view can be active at a time
- Visual feedback with distinct colors:
  - Code: Electric yellow (rgb(255 204 0))
  - Diff: Electric cyan (rgb(0 255 255))
  - Compressed: Electric pink (rgb(255 20 147))

#### Shade-based Commit Differentiation
Compressed diffs use tailwind-inspired shade variations to distinguish commits:
- Each commit gets a unique shade (100-900 scale)
- Additions use NeonSurge success spectrum colors
- Deletions use NeonSurge error spectrum colors
- Hover tooltips show commit metadata (hash, message, author, date)
- Electric yellow hover effect for enhanced visibility

#### Enhanced Features
- **Path normalization**: Handles Windows paths with backslashes correctly
- **Verbose mode improvements**: More detailed debugging output
- **Double-spacing fix**: Removed unnecessary newlines in HTML generation
- **R language support**: Full support for R6, S3, S4 classes and methods

#### Recent Bug Fixes (September 15, 2025)
- **Fixed diff ordering**: Diffs now show older → newer (chronological) instead of reversed
- **Unified diff copy**: Single copy button exports proper unified diff format
- **Shade-colored headers**: Commit headers in compressed view match their diff colors
- **Clickable diff lines**: Click any change in compressed view to jump to its diff
- **Centralized color definitions**: Single source of truth for shade colors
- **Removed blank line ignoring**: Preserves accurate line numbers in compressed view

#### Recent Bug Fixes (October 18, 2025)
- **Fixed compressed diff truncation**: Compressed diff now shows ALL lines that ever existed, not just final version lines
  - **Problem**: When code was reduced (e.g., 700 lines → 22 lines), compressed diff only showed lines 1-22
  - **Root cause**: Loop iterated through `finalLines.Count` instead of maximum line number with changes
  - **Fix**: Calculate `maxLineNum = Math.Max(finalLines.Count, maxChangeLineNum)` to iterate through all affected lines
  - **Result**: Deleted methods at lines 23-700+ now appear in compressed diff output
  - **Impact**: `Get-CompressedDiffText` and `Get-CompressedDiff` functions in Track-CodeEvolution.ps1:1250-1270 and 1460-1480

### Technical Requirements

- **web-tree-sitter**: Version 0.25.x required (supports language version 15)
- **tree-sitter CLI**: Version 0.25.9 or later
- **Emscripten SDK**: Required for building WASM files (included in code_evolver/emsdk)
- **Initialization**: Uses `TreeSitter.Parser.init()` then `new TreeSitter.Parser()`
- **WASM files**: All grammars compiled with tree-sitter CLI 0.25.x and emcc from emsdk

### Building Grammar WASM Files (September 2025 Method)

All grammar WASM files are located in `code_evolver/grammars/`. If you need to rebuild them:

#### Prerequisites
1. **Emscripten SDK**: Already included at `code_evolver/emsdk/`
2. **tree-sitter CLI**: Install via `npm install -g tree-sitter-cli@0.25.9`
3. **Node.js**: Available at `/c/nvm4w/nodejs/` (Windows NVM)

#### Activation and Build Process

```bash
# 1. Activate Emscripten SDK (Windows PowerShell)
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\jacks\experiments\WebStormProjects\vibe-reader-extension\vibe_tools\code_evolver\emsdk\emsdk_env.ps1"

# 2. Set environment variables for Git Bash
export PATH="/c/Users/jacks/experiments/WebStormProjects/vibe-reader-extension/vibe_tools/code_evolver/emsdk:/c/Users/jacks/experiments/WebStormProjects/vibe-reader-extension/vibe_tools/code_evolver/emsdk/upstream/emscripten:$PATH"
export EMSDK_PYTHON="C:/Users/jacks/experiments/WebStormProjects/vibe-reader-extension/vibe_tools/code_evolver/emsdk/python/3.13.3_64bit/python.exe"

# 3. Build JavaScript Grammar
git clone https://github.com/tree-sitter/tree-sitter-javascript
cd tree-sitter-javascript
/c/nvm4w/nodejs/npx tree-sitter generate
emcc src/parser.c src/scanner.c -o tree-sitter-javascript.wasm -I./src -Os -fPIC -s WASM=1 -s SIDE_MODULE=2 -s EXPORTED_FUNCTIONS="['_tree_sitter_javascript']"

# 4. Build Python Grammar
git clone https://github.com/tree-sitter/tree-sitter-python
cd tree-sitter-python
/c/nvm4w/nodejs/npx tree-sitter generate
emcc src/parser.c src/scanner.c -o tree-sitter-python.wasm -I./src -Os -fPIC -s WASM=1 -s SIDE_MODULE=2 -s EXPORTED_FUNCTIONS="['_tree_sitter_python']"

# 5. Build Bash Grammar
git clone https://github.com/tree-sitter/tree-sitter-bash
cd tree-sitter-bash
/c/nvm4w/nodejs/npx tree-sitter generate
emcc src/parser.c src/scanner.c -o tree-sitter-bash.wasm -I./src -Os -fPIC -s WASM=1 -s SIDE_MODULE=2 -s EXPORTED_FUNCTIONS="['_tree_sitter_bash']"

# 6. Build PowerShell Grammar (Airbus version works best)
git clone https://github.com/Airbus-CERT/tree-sitter-powershell
cd tree-sitter-powershell
/c/nvm4w/nodejs/npx tree-sitter generate
# Note: PowerShell uses lowercase in the export function name
emcc src/parser.c src/scanner.c -o tree-sitter-powershell.wasm -I./src -Os -fPIC -s WASM=1 -s SIDE_MODULE=2 -s EXPORTED_FUNCTIONS="['_tree_sitter_powershell']"

# 7. Build R Grammar
git clone https://github.com/r-lib/tree-sitter-r
cd tree-sitter-r
/c/nvm4w/nodejs/npx tree-sitter generate
emcc src/parser.c src/scanner.c -o tree-sitter-r.wasm -I./src -Os -fPIC -s WASM=1 -s SIDE_MODULE=2 -s EXPORTED_FUNCTIONS="['_tree_sitter_r']"

# 8. Copy all WASM files to grammars directory
cp *.wasm ../code_evolver/grammars/
```

#### Important Notes for Building

- **Python Path Issues**: The emcc command may fail with "Python not found" on Windows. Use the EMSDK_PYTHON environment variable to point to the Python included with emsdk.
- **NPX Path**: On Windows with NVM, use the full path `/c/nvm4w/nodejs/npx` instead of just `npx`
- **Function Names**: Each grammar exports a function with its language name (e.g., `_tree_sitter_javascript`). PowerShell uses lowercase `_tree_sitter_powershell`.
- **Scanner Files**: Some grammars have `scanner.c` or `scanner.cc` files that must be included in the emcc command
- **Latest Versions**: All grammars rebuilt with tree-sitter CLI 0.25.9 and web-tree-sitter 0.25.x

## Development History

### Key Evolution from Parent Repository (vibe-reader-extension)

The Code Evolution Tracker was developed through the following commits in the parent repository:

1. **8b6247e** - Initial implementation

   - Created `Track-CodeEvolution-Final.ps1`: PowerShell orchestrator with Git integration
   - Created `acorn-parser.js`: Node.js CLI tool using Acorn AST parser
   - Established core architecture for tracking code evolution
   - Added filtering by class name and inheritance detection

2. **0b96c0c** - Scroll synchronization

   - Added synchronized scrolling between diff views in HTML reports
   - Improved side-by-side diff navigation

3. **0d9c1cc** - Enhanced diff UI

   - Implemented resizable panels for diff views
   - Improved change visualization with better highlighting
   - Enhanced user interaction in HTML reports

4. **6c20371** - Unified diff export (with JSON escape bug)

   - Added unified diff export functionality
   - Implemented modal visualization for diffs
   - Note: Had JSON escaping issues that were fixed in later commits

5. **5b464c0** - Refactoring

   - Removed unified diff modal functionality
   - Simplified UI interaction model

6. **c9d7f50** - Unified diff toggle

   - Re-implemented unified diff with toggle functionality
   - Integrated HTML content generation
   - Fixed previous JSON escaping issues

7. **1a5240e** - Compressed diff format

   - Added revolutionary compressed diff export format
   - Reduces 80,000+ lines to ~5,000 for LLM processing
   - Enhanced UI with better export options

8. **af52740** - NeonSurge theme
   - Updated UI to high-contrast NeonSurge color scheme
   - Bright green additions, electric pink deletions
   - Pure black background for maximum readability

### File Renaming for vibe_tools

When extracted to vibe_tools as an independent project:

- `Track-CodeEvolution-Final.ps1` → `Track-CodeEvolution.ps1`
- `acorn-parser.js` → `lib/parsers/javascript-parser.js`
