#!/usr/bin/env node

/*
 * Reference Parser for Code Symbol Analysis
 *
 * Finds symbol definitions and references using tree-sitter AST parsing
 * Supports: JavaScript, Python, PowerShell, Bash, R, C#
 */

const fs = require('fs');
const path = require('path');
const TreeSitter = require('web-tree-sitter');

// Language detection based on file extension
function detectLanguage(filePath) {
  const ext = path.extname(filePath).toLowerCase();

  const languageMap = {
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.mjs': 'javascript',
    '.cjs': 'javascript',
    '.ts': 'javascript',
    '.tsx': 'javascript',
    '.py': 'python',
    '.ps1': 'powershell',
    '.psm1': 'powershell',
    '.psd1': 'powershell',
    '.sh': 'bash',
    '.bash': 'bash',
    '.r': 'r',
    '.R': 'r',
    '.cs': 'csharp',
    '.csx': 'csharp'
  };

  return languageMap[ext] || 'unknown';
}

// Parser and language initialization
let parserInitialized = false;
let parser = null;
const loadedLanguages = new Map();

// Initialize parser once
async function initParser() {
  if (parserInitialized) return parser;

  try {
    await TreeSitter.Parser.init();
    parser = new TreeSitter.Parser();
    parserInitialized = true;
  } catch (error) {
    console.error("Failed to initialize parser:", error.message);
    throw error;
  }
  return parser;
}

// Load language grammar from WASM file
async function loadLanguage(language) {
  if (loadedLanguages.has(language)) {
    return loadedLanguages.get(language);
  }

  const grammarFiles = {
    'javascript': 'tree-sitter-javascript.wasm',
    'python': 'tree-sitter-python.wasm',
    'powershell': 'tree-sitter-powershell.wasm',
    'bash': 'tree-sitter-bash.wasm',
    'r': 'tree-sitter-r.wasm',
    'csharp': 'tree-sitter-c-sharp.wasm'
  };

  const grammarFile = grammarFiles[language];
  if (!grammarFile) {
    console.error(`No grammar available for language: ${language}`);
    return null;
  }

  const grammarPath = path.join(__dirname, '..', 'grammars', grammarFile);

  if (!fs.existsSync(grammarPath)) {
    console.error(`Grammar file not found: ${grammarPath}`);
    return null;
  }

  try {
    const languageObj = await TreeSitter.Language.load(grammarPath);
    loadedLanguages.set(language, languageObj);
    return languageObj;
  } catch (error) {
    console.error(`Failed to load grammar for ${language}:`, error.message);
    return null;
  }
}

// Extract symbols from a file
async function extractSymbols(filePath, filters = []) {
  const code = fs.readFileSync(filePath, 'utf8');
  const language = detectLanguage(filePath);

  await initParser();
  const langObj = await loadLanguage(language);

  if (!langObj) {
    throw new Error(`Unsupported language: ${language}`);
  }

  parser.setLanguage(langObj);
  const tree = parser.parse(code);

  const symbols = [];

  function walkForSymbols(node, ancestors = []) {
    // Extract symbols based on node type and language
    const symbol = extractSymbol(node, ancestors, language);
    if (symbol) {
      // Apply filters
      if (filters.includes('--exclude-globals') && symbol.type === 'global') return;
      if (filters.includes('--exclude-exports') && symbol.type === 'export') return;
      if (filters.includes('--exclude-constants') && symbol.type === 'constant') return;

      symbols.push(symbol);
    }

    // Recurse through children
    const newAncestors = [...ancestors, node];
    for (let child of node.children) {
      walkForSymbols(child, newAncestors);
    }
  }

  walkForSymbols(tree.rootNode);
  return symbols;
}

// Extract symbol from node
function extractSymbol(node, ancestors, language) {
  switch (language) {
    case 'javascript':
      return extractJavaScriptSymbol(node, ancestors);
    case 'python':
      return extractPythonSymbol(node, ancestors);
    case 'csharp':
      return extractCSharpSymbol(node, ancestors);
    case 'powershell':
      return extractPowerShellSymbol(node, ancestors);
    case 'bash':
      return extractBashSymbol(node, ancestors);
    case 'r':
      return extractRSymbol(node, ancestors);
    default:
      return null;
  }
}

// JavaScript symbol extraction
function extractJavaScriptSymbol(node, ancestors) {
  switch (node.type) {
    case 'class_declaration':
      return {
        name: node.childForFieldName('name')?.text,
        type: 'class',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'method_definition':
      const methodName = node.childForFieldName('name')?.text;
      const parentClass = ancestors.find(a => a.type === 'class_declaration');
      return methodName ? {
        name: methodName,
        type: 'method',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1,
        parent: parentClass?.childForFieldName('name')?.text
      } : null;

    case 'function_declaration':
      return {
        name: node.childForFieldName('name')?.text,
        type: 'function',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'lexical_declaration':
      if (node.firstChild?.text === 'const') {
        const declarator = node.childForFieldName('declarator');
        const constName = declarator?.childForFieldName('name')?.text;
        const isTopLevel = !ancestors.some(a =>
          a.type === 'function_declaration' ||
          a.type === 'arrow_function' ||
          a.type === 'function_expression'
        );

        if (constName && isTopLevel) {
          return {
            name: constName,
            type: 'constant',
            line: node.startPosition.row + 1,
            endLine: node.endPosition.row + 1
          };
        }
      }
      break;

    case 'export_statement':
      const exported = node.childForFieldName('declaration');
      if (exported) {
        const exportName = getExportedName(exported);
        if (exportName) {
          return {
            name: exportName,
            type: 'export',
            line: node.startPosition.row + 1,
            endLine: node.endPosition.row + 1
          };
        }
      }
      break;
  }
  return null;
}

// Python symbol extraction
function extractPythonSymbol(node, ancestors) {
  switch (node.type) {
    case 'class_definition':
      return {
        name: node.childForFieldName('name')?.text,
        type: 'class',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'function_definition':
      const functionName = node.childForFieldName('name')?.text;
      const isInClass = ancestors.some(a => a.type === 'class_definition');
      return functionName ? {
        name: functionName,
        type: isInClass ? 'method' : 'function',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      } : null;

    case 'assignment':
      const varName = node.childForFieldName('left')?.text;
      if (varName && /^[A-Z][A-Z_0-9]*$/.test(varName)) {
        const isTopLevel = !ancestors.some(a =>
          a.type === 'function_definition' || a.type === 'class_definition'
        );
        if (isTopLevel) {
          return {
            name: varName,
            type: 'constant',
            line: node.startPosition.row + 1,
            endLine: node.endPosition.row + 1
          };
        }
      }
      break;
  }
  return null;
}

// C# symbol extraction
function extractCSharpSymbol(node, ancestors) {
  switch (node.type) {
    case 'class_declaration':
      return {
        name: node.childForFieldName('name')?.text,
        type: 'class',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'interface_declaration':
      return {
        name: node.childForFieldName('name')?.text,
        type: 'interface',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'method_declaration':
      return {
        name: node.childForFieldName('name')?.text,
        type: 'method',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'constructor_declaration':
      const parentClass = ancestors.find(a => a.type === 'class_declaration');
      const ctorName = parentClass?.childForFieldName('name')?.text;
      return ctorName ? {
        name: ctorName,
        type: 'constructor',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      } : null;

    case 'field_declaration':
      const fieldDeclarators = node.descendantsOfType('variable_declarator');
      const modifiers = node.childForFieldName('modifiers')?.text || '';

      return fieldDeclarators.map(declarator => {
        const fieldName = declarator.childForFieldName('name')?.text;
        if (fieldName) {
          const isConstant = modifiers.includes('const') ||
            (modifiers.includes('readonly') && modifiers.includes('static'));
          return {
            name: fieldName,
            type: isConstant ? 'constant' : 'field',
            line: node.startPosition.row + 1,
            endLine: node.endPosition.row + 1
          };
        }
        return null;
      }).filter(Boolean)[0];
  }
  return null;
}

// PowerShell symbol extraction
function extractPowerShellSymbol(node, ancestors) {
  switch (node.type) {
    case 'class_statement':
    case 'class_definition':
      return {
        name: node.childForFieldName('name')?.text || node.children.find(c => c.type === 'simple_name')?.text,
        type: 'class',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };

    case 'function_statement':
    case 'function_definition':
      return {
        name: node.childForFieldName('name')?.text || node.children[1]?.text,
        type: 'function',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };
  }
  return null;
}

// Bash symbol extraction
function extractBashSymbol(node, ancestors) {
  if (node.type === 'function_definition') {
    return {
      name: node.childForFieldName('name')?.text,
      type: 'function',
      line: node.startPosition.row + 1,
      endLine: node.endPosition.row + 1
    };
  }
  return null;
}

// R symbol extraction
function extractRSymbol(node, ancestors) {
  if (node.type === 'binary_operator' && node.childForFieldName('operator')?.text === '<-') {
    const left = node.childForFieldName('lhs');
    const right = node.childForFieldName('rhs');

    if (right?.text?.startsWith('function')) {
      return {
        name: left?.text,
        type: 'function',
        line: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1
      };
    }
  }
  return null;
}

// Get exported name helper
function getExportedName(exportNode) {
  if (exportNode.type === 'function_declaration') {
    return exportNode.childForFieldName('name')?.text;
  } else if (exportNode.type === 'class_declaration') {
    return exportNode.childForFieldName('name')?.text;
  } else if (exportNode.type === 'lexical_declaration') {
    const declarator = exportNode.childForFieldName('declarator');
    return declarator?.childForFieldName('name')?.text;
  }
  return null;
}

// Find references to symbols in a file
async function findReferences(filePath, symbols) {
  const code = fs.readFileSync(filePath, 'utf8');
  const language = detectLanguage(filePath);

  await initParser();
  const langObj = await loadLanguage(language);

  if (!langObj) {
    throw new Error(`Unsupported language: ${language}`);
  }

  parser.setLanguage(langObj);
  const tree = parser.parse(code);

  const references = [];
  const symbolMap = new Map();
  symbols.forEach(sym => symbolMap.set(sym.name, sym));

  function walkForReferences(node, ancestors = []) {
    const nodeLine = node.startPosition.row + 1;

    for (const [symbolName, symbolData] of symbolMap) {
      if (isReference(node, symbolName, symbolData, language)) {
        const context = getContainingContext(ancestors);

        references.push({
          symbol: symbolName,
          line: nodeLine,
          context: context,
          usage: getUsageType(node, symbolName, language)
        });
      }
    }

    const newAncestors = [...ancestors, node];
    for (let child of node.children) {
      walkForReferences(child, newAncestors);
    }
  }

  walkForReferences(tree.rootNode);
  return references;
}

// Check if a node is a reference to a symbol
function isReference(node, symbolName, symbolData, language) {
  switch (language) {
    case 'javascript':
      return isJavaScriptReference(node, symbolName);
    case 'python':
      return isPythonReference(node, symbolName);
    case 'csharp':
      return isCSharpReference(node, symbolName);
    case 'powershell':
      return isPowerShellReference(node, symbolName);
    default:
      return node.type === 'identifier' && node.text === symbolName;
  }
}

// JavaScript reference detection
function isJavaScriptReference(node, symbolName) {
  if (node.type === 'call_expression') {
    const funcNode = node.childForFieldName('function');
    if (funcNode?.text === symbolName) return true;

    if (funcNode?.type === 'member_expression') {
      const prop = funcNode.childForFieldName('property');
      if (prop?.text === symbolName) return true;
    }
  }

  if (node.type === 'new_expression') {
    const constructor = node.childForFieldName('constructor');
    if (constructor?.text === symbolName) return true;
  }

  if (node.type === 'identifier' && node.text === symbolName) {
    const parent = node.parent;
    if (parent?.type !== 'variable_declarator' &&
        parent?.type !== 'function_declaration' &&
        parent?.type !== 'class_declaration') {
      return true;
    }
  }

  return false;
}

// Python reference detection
function isPythonReference(node, symbolName) {
  if (node.type === 'call') {
    const funcNode = node.childForFieldName('function');
    if (funcNode?.text === symbolName) return true;

    if (funcNode?.type === 'attribute') {
      const attr = funcNode.childForFieldName('attribute');
      if (attr?.text === symbolName) return true;
    }
  }

  if (node.type === 'identifier' && node.text === symbolName) {
    const parent = node.parent;
    if (parent?.type !== 'function_definition' &&
        parent?.type !== 'class_definition' &&
        parent?.type !== 'assignment' &&
        parent?.type !== 'parameters') {
      return true;
    }
  }

  return false;
}

// C# reference detection
function isCSharpReference(node, symbolName) {
  // Method calls
  if (node.type === 'invocation_expression') {
    const funcNode = node.childForFieldName('function');
    if (funcNode?.text === symbolName) return true;

    if (funcNode?.type === 'member_access_expression') {
      const name = funcNode.childForFieldName('name');
      if (name?.text === symbolName) return true;
    }
  }

  // Object creation
  if (node.type === 'object_creation_expression') {
    const type = node.childForFieldName('type');
    if (type?.text === symbolName) return true;
  }

  // Field/property access (including _fieldName patterns)
  if (node.type === 'member_access_expression') {
    const name = node.childForFieldName('name');
    if (name?.text === symbolName) return true;
  }

  // Simple identifier usage (fields, local variables, parameters)
  if (node.type === 'identifier' && node.text === symbolName) {
    const parent = node.parent;

    // Check if it's being accessed/used, not declared
    if (parent?.type === 'field_declaration' ||
        parent?.type === 'variable_declaration' ||
        parent?.type === 'parameter' ||
        parent?.type === 'property_declaration') {
      // Check if this is the declaration or a use
      const nameNode = parent.childForFieldName('name');
      if (nameNode?.text === symbolName) {
        return false; // This is the declaration, not a reference
      }
    }

    // Allow references in all other contexts
    return true;
  }

  // Assignment targets (e.g., _disposed = true)
  if (node.type === 'assignment_expression') {
    const left = node.childForFieldName('left');
    if (left?.text === symbolName) return true;
  }

  // Type references
  if (node.type === 'type_identifier' && node.text === symbolName) {
    const parent = node.parent;
    // Exclude the declaration itself
    if (parent?.type !== 'class_declaration' &&
        parent?.type !== 'interface_declaration' &&
        parent?.type !== 'struct_declaration') {
      return true;
    }
  }

  return false;
}

// PowerShell reference detection
function isPowerShellReference(node, symbolName) {
  if (node.type === 'command' || node.type === 'command_invocation') {
    const cmdName = node.firstChild?.text;
    if (cmdName === symbolName) return true;
  }

  const varName = symbolName.startsWith('$') ? symbolName : `$${symbolName}`;
  if (node.type === 'variable' && node.text === varName) {
    const parent = node.parent;
    if (parent?.type !== 'variable_assignment') {
      return true;
    }
  }

  if (node.type === 'simple_name' && node.text === symbolName) {
    return true;
  }

  return false;
}

// Get containing function/method context
function getContainingContext(ancestors) {
  for (let i = ancestors.length - 1; i >= 0; i--) {
    const ancestor = ancestors[i];

    if (ancestor.type === 'function_declaration' ||
        ancestor.type === 'function_definition' ||
        ancestor.type === 'method_definition' ||
        ancestor.type === 'method_declaration' ||
        ancestor.type === 'arrow_function') {

      const name = ancestor.childForFieldName('name')?.text;
      if (name) return name;
    }

    if (ancestor.type === 'class_declaration' ||
        ancestor.type === 'class_definition') {
      const className = ancestor.childForFieldName('name')?.text;
      if (className) {
        for (let j = i + 1; j < ancestors.length; j++) {
          if (ancestors[j].type === 'method_definition' ||
              ancestors[j].type === 'method_declaration') {
            const methodName = ancestors[j].childForFieldName('name')?.text;
            if (methodName) return `${className}.${methodName}`;
          }
        }
        return className;
      }
    }
  }

  return null;
}

// Determine usage type
function getUsageType(node, symbolName, language) {
  const parent = node.parent;

  if (parent?.type?.includes('call') || parent?.type?.includes('invocation')) {
    return 'call';
  }

  if (parent?.type?.includes('new') || parent?.type?.includes('creation')) {
    return 'instantiation';
  }

  if (parent?.type?.includes('import') || parent?.type?.includes('require')) {
    return 'import';
  }

  if (parent?.type?.includes('extends') || parent?.type?.includes('inherits')) {
    return 'inheritance';
  }

  return 'reference';
}

// Main CLI handler
async function main() {
  if (process.argv.length < 3) {
    console.error("Usage: node reference-parser.js @<params.json>");
    process.exit(1);
  }

  if (!process.argv[2].startsWith('@')) {
    console.error("Usage: node reference-parser.js @<params.json>");
    process.exit(1);
  }

  const argFile = process.argv[2].substring(1);
  try {
    const argData = fs.readFileSync(argFile, 'utf8');
    const params = JSON.parse(argData);

    if (params.mode === 'extract') {
      const symbols = await extractSymbols(params.file, params.filters || []);
      console.log(JSON.stringify({ symbols }, null, 2));
    } else if (params.mode === 'references') {
      const references = await findReferences(params.file, params.symbols);
      console.log(JSON.stringify({ references }, null, 2));
    } else {
      console.error("Invalid mode. Use 'extract' or 'references'");
      process.exit(1);
    }
  } catch (error) {
    console.log(JSON.stringify({ error: error.message }));
    process.exit(1);
  }
}

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { extractSymbols, findReferences, detectLanguage };
}

// Run if called directly
if (require.main === module) {
  main();
}