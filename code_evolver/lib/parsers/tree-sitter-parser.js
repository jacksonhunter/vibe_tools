#!/usr/bin/env node

/*
 * Tree-sitter Multi-Language Parser with Ancestor Tracking
 *
 * Uses web-tree-sitter (WASM) to avoid Windows build tool requirements
 * Supports: JavaScript, Python, PowerShell, Bash, R
 *
 * Installation: npm install web-tree-sitter
 * Grammar files: Place .wasm files in grammars/ directory
 */

const fs = require('fs');
const path = require('path');
const TreeSitter = require('web-tree-sitter');

let detectedSegments = [];
let currentContext = null;
let currentLanguageConfig = null;

// Language detection based on file extension
function detectLanguage(filePath) {
  const ext = path.extname(filePath).toLowerCase();

  const languageMap = {
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.mjs': 'javascript',
    '.cjs': 'javascript',
    '.py': 'python',
    '.ps1': 'powershell',
    '.psm1': 'powershell',
    '.psd1': 'powershell',
    '.sh': 'bash',
    '.bash': 'bash',
    '.r': 'r',
    '.R': 'r'
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
    // web-tree-sitter requires init() first
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

  // Map language to grammar file
  const grammarFiles = {
    'javascript': 'tree-sitter-javascript.wasm',
    'python': 'tree-sitter-python.wasm',
    'powershell': 'tree-sitter-powershell.wasm',
    'bash': 'tree-sitter-bash.wasm',
    'r': 'tree-sitter-r.wasm'
  };

  const grammarFile = grammarFiles[language];
  if (!grammarFile) {
    console.error(`No grammar available for language: ${language}`);
    return null;
  }

  const grammarPath = path.join(__dirname, '..', '..', 'grammars', grammarFile);

  if (!fs.existsSync(grammarPath)) {
    console.error(`Grammar file not found: ${grammarPath}`);
    console.error(`Please download ${grammarFile} to the grammars directory`);
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

// Tree-sitter AST traversal with ancestor tracking (the key trick!)
function traverseWithAncestors(node, ancestors, visitor) {
  // Call visitor with current node and ancestors
  visitor(node, ancestors);

  // Traverse children with updated ancestor chain
  const childCount = node.childCount;
  for (let i = 0; i < childCount; i++) {
    const childNode = node.child(i);
    if (childNode) {
      const newAncestors = [...ancestors, node]; // Add current node to ancestor chain
      traverseWithAncestors(childNode, newAncestors, visitor);
    }
  }
}

// Add segment with context from ancestors
function addSegment(node, type, name, ancestors, options = {}) {
  const startPosition = node.startPosition;
  const endPosition = node.endPosition;
  
  let finalName = name || "anonymous";
  let parent = options.parent || null;
  let extendsClass = options.extends || null;
  
  // Use ancestor trick for context preservation
  if (type === "method" && currentContext && currentContext.PreserveContext) {
    // Find parent class from ancestors
    for (let i = ancestors.length - 1; i >= 0; i--) {
      const ancestor = ancestors[i];
      if (ancestor.type === 'class_declaration' || ancestor.type === 'class_definition') {
        // Get class name from ancestor node
        const classNameNode = ancestor.childForFieldName('name');
        if (classNameNode) {
          const className = classNameNode.text;
          finalName = `${className}.${name}`;
          parent = className;
          break;
        }
      }
    }
  }

  detectedSegments.push({
    name: finalName,
    type,
    startLine: startPosition.row,
    endLine: endPosition.row,
    content: "", // Will be filled later
    parent: parent,
    extends: extendsClass,
  });
}

// Language-specific element extraction using tree-sitter AST
class TreeSitterExtractor {
  constructor(language) {
    this.language = language;
  }
  
  extract(tree, extractionContext) {
    detectedSegments = [];
    currentContext = extractionContext;
    
    const rootNode = tree.rootNode;
    
    // Use ancestor tracking to traverse the tree
    traverseWithAncestors(rootNode, [], (node, ancestors) => {
      this.processNode(node, ancestors);
    });
    
    return detectedSegments;
  }
  
  processNode(node, ancestors) {
    switch (this.language) {
      case 'javascript':
        this.processJavaScriptNode(node, ancestors);
        break;
      case 'python':
        this.processPythonNode(node, ancestors);
        break;
      case 'bash':
        this.processBashNode(node, ancestors);
        break;
      case 'powershell':
        this.processPowerShellNode(node, ancestors);
        break;
      case 'r':
        this.processRNode(node, ancestors);
        break;
    }
  }
  
  processJavaScriptNode(node, ancestors) {
    switch (node.type) {
      case 'class_declaration':
        const className = node.childForFieldName('name')?.text;
        const superClass = node.childForFieldName('superclass')?.text;
        if (className) {
          addSegment(node, 'class', className, ancestors, { extends: superClass });
        }
        break;
        
      case 'method_definition':
        const methodName = node.childForFieldName('name')?.text;
        if (methodName) {
          addSegment(node, 'method', methodName, ancestors);
        }
        break;
        
      case 'function_declaration':
        const functionName = node.childForFieldName('name')?.text;
        if (functionName) {
          addSegment(node, 'function', functionName, ancestors);
        }
        break;
        
      case 'lexical_declaration':
        // Handle const declarations
        if (node.firstChild?.text === 'const') {
          const declarator = node.childForFieldName('declarator');
          const constName = declarator?.childForFieldName('name')?.text;
          
          if (constName && !this.shouldExcludeConstant(constName)) {
            // Use ancestors to check if we're at top level
            const isTopLevel = !ancestors.some(ancestor => 
              ancestor.type === 'function_declaration' || 
              ancestor.type === 'arrow_function' ||
              ancestor.type === 'function_expression'
            );
            
            if (isTopLevel) {
              addSegment(node, 'constant', constName, ancestors);
            }
          }
        }
        break;
        
      case 'assignment_expression':
        // Handle global assignments like window.something = 
        const left = node.childForFieldName('left');
        if (left?.type === 'member_expression') {
          const object = left.childForFieldName('object')?.text;
          const property = left.childForFieldName('property')?.text;
          
          if ((object === 'window' || object === 'global') && property) {
            addSegment(node, 'global', property, ancestors);
          }
        }
        break;
        
      case 'export_statement':
        // Handle export declarations
        const exported = node.childForFieldName('declaration');
        if (exported) {
          const exportName = this.getExportedName(exported);
          if (exportName) {
            addSegment(node, 'export', exportName, ancestors);
          }
        }
        break;
    }
  }
  
  processPythonNode(node, ancestors) {
    switch (node.type) {
      case 'class_definition':
        const className = node.childForFieldName('name')?.text;
        const superClass = node.childForFieldName('superclasses')?.firstChild?.text;
        if (className) {
          addSegment(node, 'class', className, ancestors, { extends: superClass });
        }
        break;
        
      case 'function_definition':
        const functionName = node.childForFieldName('name')?.text;
        if (functionName) {
          // Use ancestors to determine if this is a method or function
          const isInClass = ancestors.some(ancestor => ancestor.type === 'class_definition');
          const type = isInClass ? 'method' : 'function';
          addSegment(node, type, functionName, ancestors);
        }
        break;
        
      case 'assignment':
        // Handle constants (uppercase variables at module level)
        const target = node.childForFieldName('left');
        const varName = target?.text;
        
        if (varName && /^[A-Z][A-Z_0-9]*$/.test(varName)) {
          const isTopLevel = !ancestors.some(ancestor => 
            ancestor.type === 'function_definition' || ancestor.type === 'class_definition'
          );
          
          if (isTopLevel) {
            addSegment(node, 'constant', varName, ancestors);
          }
        }
        break;
        
      case 'global_statement':
        // Handle global variable declarations
        const globalVar = node.firstChild?.nextSibling?.text;
        if (globalVar) {
          addSegment(node, 'global', globalVar, ancestors);
        }
        break;
    }
  }
  
  processBashNode(node, ancestors) {
    switch (node.type) {
      case 'function_definition':
        const functionName = node.childForFieldName('name')?.text;
        if (functionName) {
          addSegment(node, 'function', functionName, ancestors);
        }
        break;

      case 'variable_assignment':
        const varName = node.childForFieldName('name')?.text;
        const value = node.childForFieldName('value')?.text;

        // Check for readonly/declare -r patterns
        if (varName && (value?.includes('readonly') || ancestors.some(a => a.text?.includes('declare -r')))) {
          addSegment(node, 'constant', varName, ancestors);
        }
        break;

      case 'command':
        // Handle export commands
        if (node.firstChild?.text === 'export') {
          const exportVar = node.children[1]?.text;
          if (exportVar) {
            addSegment(node, 'export', exportVar, ancestors);
            addSegment(node, 'global', exportVar, ancestors);
          }
        }
        break;
    }
  }

  processPowerShellNode(node, ancestors) {

    switch (node.type) {
      case 'class_statement':
      case 'class_definition':
        const className = node.childForFieldName('name')?.text || node.children.find(c => c.type === 'simple_name')?.text;
        const baseClass = node.childForFieldName('base_class')?.text;
        if (className) {
          addSegment(node, 'class', className, ancestors, { extends: baseClass });
        }
        break;

      case 'function_statement':
      case 'function_definition':
        const functionName = node.childForFieldName('name')?.text || node.children[1]?.text;
        if (functionName) {
          addSegment(node, 'function', functionName, ancestors);
        }
        break;

      case 'method_definition':
        const methodName = node.childForFieldName('name')?.text;
        if (methodName) {
          addSegment(node, 'method', methodName, ancestors);
        }
        break;

      case 'variable_assignment':
        const varNode = node.childForFieldName('variable');
        const varName = varNode?.text;

        // Check for global/script scope
        if (varName?.includes('$global:') || varName?.includes('$script:')) {
          const cleanName = varName.replace(/\$(global|script):/, '');
          addSegment(node, 'global', cleanName, ancestors);
        }
        // Check for readonly constants
        else if (varNode?.parent?.text?.includes('[readonly]')) {
          addSegment(node, 'constant', varName?.replace('$', ''), ancestors);
        }
        break;

      case 'export_statement':
        // Handle Export-ModuleMember
        const exportTarget = node.childForFieldName('target')?.text;
        if (exportTarget) {
          addSegment(node, 'export', exportTarget, ancestors);
        }
        break;
    }
  }

  processRNode(node, ancestors) {
    switch (node.type) {
      case 'function_definition':
      case 'binary_operator':
        // Handle function <- function() or name <- function()
        if (node.type === 'binary_operator' && node.childForFieldName('operator')?.text === '<-') {
          const left = node.childForFieldName('left');
          const right = node.childForFieldName('right');

          if (right?.text?.startsWith('function')) {
            const functionName = left?.text;
            if (functionName) {
              addSegment(node, 'function', functionName, ancestors);
            }
          }
          // Check for constants (uppercase names)
          else if (left?.text && /^[A-Z][A-Z._0-9]*$/.test(left.text)) {
            addSegment(node, 'constant', left.text, ancestors);
          }
        }
        break;

      case 'assignment':
        // Handle = assignments
        const target = node.childForFieldName('left')?.text;
        if (target && /^[A-Z][A-Z._0-9]*$/.test(target)) {
          addSegment(node, 'constant', target, ancestors);
        }
        break;

      case 'call':
        // Handle assign() for global variables
        const fnName = node.childForFieldName('function')?.text;
        if (fnName === 'assign' || fnName === '<<-') {
          const varName = node.childForFieldName('arguments')?.firstChild?.text;
          if (varName) {
            addSegment(node, 'global', varName.replace(/[\"']/g, ''), ancestors);
          }
        }
        break;
    }
  }
  
  getExportedName(exportNode) {
    // Extract name from various export patterns
    if (exportNode.type === 'function_declaration') {
      return exportNode.childForFieldName('name')?.text;
    } else if (exportNode.type === 'class_declaration') {
      return exportNode.childForFieldName('name')?.text;
    } else if (exportNode.type === 'lexical_declaration') {
      const declarator = exportNode.childForFieldName('declarator');
      return declarator?.childForFieldName('name')?.text;
    }
    return 'default';
  }
  
  shouldExcludeConstant(name) {
    if (/^[a-z]$/.test(name)) return true;
    if (['i', 'j', 'k', 'idx', 'index', 'temp', 'tmp'].includes(name.toLowerCase())) return true;
    if (name.startsWith('_')) return true;
    if (name.length <= 2 && name !== name.toUpperCase()) return true;
    return false;
  }
}

// Apply extraction context filtering (shared with javascript-parser.js)
function matchesExtractionContext(segment, extractionContext) {
  if (!extractionContext) return true;
  
  if (extractionContext.Elements && extractionContext.Elements.length > 0) {
    if (!extractionContext.Elements.includes(segment.type)) return false;
  }
  
  if (extractionContext.Exclusions && extractionContext.Exclusions.includes(segment.type)) {
    return false;
  }
  
  if (extractionContext.Filters) {
    if (extractionContext.Filters.FunctionName) {
      const targetName = extractionContext.Filters.FunctionName;
      if (segment.type === 'method') {
        const methodName = segment.name.includes('.') ? segment.name.split('.').pop() : segment.name;
        if (methodName !== targetName && segment.name !== targetName) return false;
      } else {
        if (segment.name !== targetName) return false;
      }
    }
    
    if (extractionContext.Filters.ClassName && segment.name !== extractionContext.Filters.ClassName) {
      return false;
    }
    
    if (extractionContext.Filters.Extends && segment.extends !== extractionContext.Filters.Extends) {
      return false;
    }
  }
  
  return true;
}

function applyExtractionContext(segments, extractionContext, code) {
  if (!extractionContext) return segments;
  
  let filtered = segments.filter(segment => matchesExtractionContext(segment, extractionContext));
  
  if (extractionContext.ScopeFilter === 'top-level') {
    filtered = filtered.filter(segment => {
      if (segment.type === 'method') return false;
      return true;
    });
  }
  
  return filtered;
}

// Main parsing function with tree-sitter and fallbacks
async function parseCode(code, filePath, extractionContext, languageConfig) {
  const language = detectLanguage(filePath);
  console.error(`Detected language: ${language} for file: ${filePath}`);

  let segments = [];

  try {
    // Initialize parser if needed
    await initParser();

    // Try to load language grammar
    const languageObj = await loadLanguage(language);

    if (languageObj) {
      console.error(`Using tree-sitter parser for ${language}`);
      parser.setLanguage(languageObj);
      const tree = parser.parse(code);
      const extractor = new TreeSitterExtractor(language);
      segments = extractor.extract(tree, extractionContext);
    } else {
      // Fallback for unsupported languages or missing grammars
      console.error(`Tree-sitter not available for ${language}, using fallback`);

      if (language === 'javascript') {
        // Special fallback to Acorn for JavaScript
        segments = await parseWithAcornFallback(code, filePath, extractionContext);
      } else {
        // Regex fallback for other languages
        segments = parseWithRegexFallback(code, language, extractionContext);
      }
    }

    // Apply extraction context filtering
    segments = applyExtractionContext(segments, extractionContext, code);

    // Add content to segments
    const lines = code.split("\n");
    segments = segments.map(segment => ({
      ...segment,
      content: lines.slice(segment.startLine, segment.endLine + 1).join("\n"),
      lineCount: segment.endLine - segment.startLine + 1
    }));

    return segments;

  } catch (error) {
    console.error(`Error parsing ${language}:`, error.message);

    // Final fallback to regex parsing
    console.error("Using regex fallback");
    return parseWithRegexFallback(code, language, extractionContext);
  }
}

// Fallback to Acorn parser for JavaScript (reuse proven logic)
async function parseWithAcornFallback(code, filePath, extractionContext) {
  console.error("Falling back to Acorn parser for JavaScript");
  
  try {
    const acorn = require('acorn');
    const walk = require('acorn-walk');
    
    const ast = acorn.parse(code, {
      ecmaVersion: "latest",
      sourceType: "module",
      locations: true,
      allowReturnOutsideFunction: true,
      allowImportExportEverywhere: true,
      allowAwaitOutsideFunction: true,
      allowSuperOutsideMethod: true,
      allowHashBang: true,
    });
    
    // Use the same logic as javascript-parser.js
    detectedSegments = [];
    currentContext = extractionContext;
    
    // Simplified addSegment for fallback
    function addSegmentFallback(node, type, name, options = {}) {
      if (!node.loc) return;
      
      let finalName = name || "anonymous";
      if (type === "method" && extractionContext && extractionContext.PreserveContext && options.parent) {
        finalName = `${options.parent}.${name}`;
      }
      
      detectedSegments.push({
        name: finalName,
        type,
        startLine: node.loc.start.line - 1,
        endLine: node.loc.end.line - 1,
        parent: options.parent || null,
        extends: options.extends || null,
      });
    }
    
    // Use ancestor walking for context
    walk.ancestor(ast, {
      ClassDeclaration(node, ancestors) {
        const className = node.id ? node.id.name : "AnonymousClass";
        const extendsClass = node.superClass ? node.superClass.name : null;
        addSegmentFallback(node, "class", className, { extends: extendsClass });
      },
      
      MethodDefinition(node, ancestors) {
        const methodName = node.key.name || node.key.value;
        
        let parentClass = null;
        for (let i = ancestors.length - 1; i >= 0; i--) {
          if (ancestors[i].type === "ClassDeclaration" || ancestors[i].type === "ClassExpression") {
            parentClass = ancestors[i].id ? ancestors[i].id.name : "AnonymousClass";
            break;
          }
        }
        
        addSegmentFallback(node, "method", methodName, { parent: parentClass });
      },
      
      FunctionDeclaration(node, ancestors) {
        if (node.id) {
          addSegmentFallback(node, "function", node.id.name);
        }
      },
      
      // Add other node types as needed...
    });
    
    return detectedSegments;
    
  } catch (error) {
    console.error("Acorn fallback failed:", error.message);
    return parseWithRegexFallback(code, 'javascript', extractionContext);
  }
}

// Enhanced regex fallback with extraction context support
function parseWithRegexFallback(code, language, extractionContext) {
  console.error(`Using enhanced regex fallback for ${language}`);
  
  const segments = [];
  const lines = code.split('\n');
  
  // Language-specific patterns with context awareness
  const patterns = getLanguagePatterns(language);
  
  // Track class context for method name preservation
  let currentClass = null;
  let classStartLine = -1;
  
  lines.forEach((line, lineIndex) => {
    const trimmed = line.trim();
    
    // Process each pattern type
    patterns.forEach(({ regex, type, handler }) => {
      const matches = trimmed.match(regex);
      if (matches) {
        if (handler) {
          handler(matches, lineIndex, line, segments, extractionContext, currentClass);
        } else {
          // Default handler
          const name = matches[1];
          if (name) {
            const finalName = (type === 'method' && currentClass && extractionContext?.PreserveContext) 
              ? `${currentClass}.${name}` 
              : name;
            
            segments.push({
              type,
              name: finalName,
              startLine: lineIndex,
              endLine: lineIndex + 2, // Estimate
              parent: type === 'method' ? currentClass : null,
              extends: null
            });
          }
        }
      }
    });
    
    // Track class context for method preservation
    if (language === 'python') {
      const classMatch = trimmed.match(/^class\s+(\w+)/);
      if (classMatch) {
        currentClass = classMatch[1];
        classStartLine = lineIndex;
      } else if (currentClass && lineIndex > classStartLine) {
        const indent = line.length - line.trimStart().length;
        if (trimmed && indent === 0 && !trimmed.startsWith('#')) {
          currentClass = null;
        }
      }
    }
  });
  
  return segments;
}

function getLanguagePatterns(language) {
  const patterns = {
    python: [
      { 
        regex: /^class\s+(\w+)(?:\(([^)]+)\))?:/, 
        type: "class",
        handler: (matches, lineIndex, line, segments, ctx, currentClass) => {
          segments.push({
            type: 'class',
            name: matches[1],
            startLine: lineIndex,
            endLine: lineIndex + 10, // Estimate
            extends: matches[2]?.trim() || null,
            parent: null
          });
        }
      },
      { regex: /^def\s+(\w+)/, type: "function" }, // Will be handled as method if in class
      { regex: /^([A-Z][A-Z_0-9]*)\s*=/, type: "constant" },
      { regex: /^global\s+(\w+)/, type: "global" }
    ],
    
    powershell: [
      { regex: /^class\s+(\w+)/i, type: "class" },
      { regex: /^function\s+([\w-]+)/i, type: "function" },
      { regex: /^\s*function\s+([\w-]+)/i, type: "function" },  // Allow indented functions
      { regex: /^\$(global|script):(\w+)/i, type: "global" },
      { regex: /^\s*\[(\w+)\]\s*(\w+)\s*\(/i, type: "method" }  // Class methods
    ],
    
    bash: [
      { regex: /^(\w+)\s*\(\s*\)\s*\{/, type: "function" },
      { regex: /^function\s+(\w+)/, type: "function" },
      { regex: /^readonly\s+(\w+)=/, type: "constant" },
      { regex: /^export\s+(\w+)/, type: "export" }
    ],
    
    r: [
      { regex: /^(\w+(?:\.\w+)*)\s*<-\s*function/, type: "function" },
      { regex: /^([A-Z][A-Z._0-9]*)\s*<-/, type: "constant" }
    ]
  };
  
  return patterns[language] || patterns.python; // Default fallback
}

// Command line interface
async function main() {
  if (process.argv.length < 3) {
    console.error("Usage: node tree-sitter-parser.js <file> [--extraction-context JSON] [--language-config JSON]");
    process.exit(1);
  }

  const filePath = process.argv[2];
  const args = process.argv.slice(3);

  let extractionContext = null;
  let languageConfig = null;

  for (let i = 0; i < args.length; i += 2) {
    if (args[i] === "--extraction-context" && i + 1 < args.length) {
      try {
        // Support reading from file if argument starts with @
        if (args[i + 1].startsWith('@')) {
          const contextFile = args[i + 1].substring(1);
          const contextData = fs.readFileSync(contextFile, 'utf8');
          extractionContext = JSON.parse(contextData);
        } else {
          extractionContext = JSON.parse(args[i + 1]);
        }
      } catch (error) {
        console.error("Invalid extraction context JSON:", error.message);
        process.exit(1);
      }
    } else if (args[i] === "--language-config" && i + 1 < args.length) {
      try {
        // Support reading from file if argument starts with @
        if (args[i + 1].startsWith('@')) {
          const configFile = args[i + 1].substring(1);
          const configData = fs.readFileSync(configFile, 'utf8');
          languageConfig = JSON.parse(configData);
        } else {
          languageConfig = JSON.parse(args[i + 1]);
        }
      } catch (error) {
        console.error("Invalid language config JSON:", error.message);
        process.exit(1);
      }
    }
  }

  try {
    if (!fs.existsSync(filePath)) {
      console.error(`File not found: ${filePath}`);
      process.exit(1);
    }

    console.error(`Parsing file: ${filePath}`);
    const code = fs.readFileSync(filePath, "utf8");
    const segments = await parseCode(code, filePath, extractionContext, languageConfig);

    const result = {
      filePath: filePath,
      language: detectLanguage(filePath),
      totalSegments: segments.length,
      filteredSegments: segments.length,
      segments: segments.map(segment => ({
        type: segment.type,
        name: segment.name,
        startLine: segment.startLine,
        endLine: segment.endLine,
        content: segment.content,
        extends: segment.extends || undefined,
        parent: segment.parent || undefined,
        lineCount: segment.lineCount,
      }))
    };

    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error("Error parsing file:", error.message);
    process.exit(1);
  }
}

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { parseCode, detectLanguage, TreeSitterExtractor };
}

// Run main function only if called directly
if (require.main === module) {
  main();
}
