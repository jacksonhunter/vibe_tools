# Tree-sitter Grammar WASM Files

This directory should contain the WASM grammar files for tree-sitter parsers.

## Required Files

- `tree-sitter-javascript.wasm` - JavaScript/JSX parser
- `tree-sitter-python.wasm` - Python parser
- `tree-sitter-powershell.wasm` - PowerShell parser
- `tree-sitter-bash.wasm` - Bash/Shell parser
- `tree-sitter-r.wasm` - R language parser

## Getting Grammar Files

### Option 1: Download Pre-built WASM Files

1. **JavaScript**: Available from [tree-sitter-javascript releases](https://github.com/tree-sitter/tree-sitter-javascript/releases)
2. **Python**: Available from [tree-sitter-python releases](https://github.com/tree-sitter/tree-sitter-python/releases)
3. **Bash**: Available from [tree-sitter-bash releases](https://github.com/tree-sitter/tree-sitter-bash/releases)
4. **PowerShell**: Check [@swimm/tree-sitter-powershell](https://www.npmjs.com/package/@swimm/tree-sitter-powershell) or [PowerShell/tree-sitter-PowerShell](https://github.com/PowerShell/tree-sitter-PowerShell)
5. **R**: Check [@davisvaughan/tree-sitter-r](https://www.npmjs.com/package/@davisvaughan/tree-sitter-r) or [r-lib/tree-sitter-r](https://github.com/r-lib/tree-sitter-r)

### Option 2: Build from Source

If pre-built WASM files aren't available, you can build them using the tree-sitter CLI with Emscripten:

```bash
# Install tree-sitter CLI
npm install -g tree-sitter-cli

# Clone the grammar repository
git clone https://github.com/tree-sitter/tree-sitter-javascript
cd tree-sitter-javascript

# Build WASM (requires Emscripten)
tree-sitter build-wasm

# Copy the generated .wasm file to this directory
cp tree-sitter-javascript.wasm ../path/to/grammars/
```

### Option 3: Extract from npm packages

Some packages include WASM files in their distribution:

```bash
# Install package temporarily
npm install tree-sitter-javascript

# Find and copy the WASM file
find node_modules/tree-sitter-javascript -name "*.wasm" -exec cp {} ./grammars/ \;

# Uninstall if not needed
npm uninstall tree-sitter-javascript
```

## Fallback Behavior

If a WASM file is not available:
- **JavaScript**: Falls back to Acorn parser (pure JS, no WASM needed)
- **Other languages**: Falls back to regex-based parsing (less accurate but functional)

## Testing

After adding WASM files, test with:

```powershell
node lib/parsers/tree-sitter-parser.js test.js
```

The parser will report which languages have WASM support available.