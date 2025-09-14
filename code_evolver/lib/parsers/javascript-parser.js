#!/usr/bin/env node

// Node.js parser that uses the exact Acorn logic from js_segmenter.html
const fs = require('fs');
const path = require('path');

// Import Acorn (you'll need to install these)
const acorn = require('acorn');
const walk = require('acorn-walk');

let detectedSegments = [];
let currentContext = null;
let currentClassContext = null;

// Global detection patterns
function detectGlobals(code) {
  const globalPatterns = [
    /window\.(\w+)\s*=/, // window.something = 
    /global\.(\w+)\s*=/, // global.something = 
    /globalThis\.(\w+)\s*=/, // globalThis.something = 
    /if\s*\(\s*!window\.(\w+)\s*\)/, // if (!window.something) - singleton guards
    /if\s*\(\s*!global\.(\w+)\s*\)/, // if (!global.something)
    /\(\s*function\s*\(\s*\)\s*\{[\s\S]*?window\.(\w+)/, // IIFE with window assignment
    /\(\s*function\s*\(\s*\)\s*\{[\s\S]*?global\.(\w+)/ // IIFE with global assignment
  ];
  
  const globals = [];
  globalPatterns.forEach(pattern => {
    let match;
    while ((match = pattern.exec(code)) !== null) {
      globals.push(match[1]);
    }
  });
  
  return globals;
}

// Check if a constant name should be excluded (meaningless constants)
function shouldExcludeConstant(name, context) {
  // Single letter variables (often loop counters)
  if (/^[a-z]$/.test(name)) return true;
  
  // Common loop variable names
  if (['i', 'j', 'k', 'idx', 'index', 'temp', 'tmp'].includes(name.toLowerCase())) return true;
  
  // Variables starting with underscore (often private/temp)
  if (name.startsWith('_')) return true;
  
  // Very short names that aren't uppercase (likely temp vars)
  if (name.length <= 2 && name !== name.toUpperCase()) return true;
  
  return false;
}

// Check if segment matches extraction context
function matchesExtractionContext(segment, extractionContext) {
  if (!extractionContext) return true;
  
  // Check if element type is in the requested elements
  if (extractionContext.Elements && extractionContext.Elements.length > 0) {
    if (!extractionContext.Elements.includes(segment.type)) return false;
  }
  
  // Check exclusions
  if (extractionContext.Exclusions && extractionContext.Exclusions.includes(segment.type)) {
    return false;
  }
  
  // Apply filters
  if (extractionContext.Filters) {
    // Function name filter
    if (extractionContext.Filters.FunctionName) {
      const targetName = extractionContext.Filters.FunctionName;
      // For methods, check both the method name and the full "ClassName.methodName"
      if (segment.type === 'method') {
        const methodName = segment.name.includes('.') ? segment.name.split('.').pop() : segment.name;
        if (methodName !== targetName && segment.name !== targetName) return false;
      } else {
        if (segment.name !== targetName) return false;
      }
    }
    
    // Class name filter
    if (extractionContext.Filters.ClassName && segment.name !== extractionContext.Filters.ClassName) {
      return false;
    }
    
    // Extends filter
    if (extractionContext.Filters.Extends && segment.extends !== extractionContext.Filters.Extends) {
      return false;
    }
  }
  
  return true;
}

// Apply post-processing based on extraction context
function applyExtractionContext(segments, extractionContext, code) {
  if (!extractionContext) return segments;
  
  let filtered = segments.filter(segment => matchesExtractionContext(segment, extractionContext));
  
  // Handle scope filtering
  if (extractionContext.ScopeFilter === 'top-level') {
    // Only keep top-level elements (not nested)
    filtered = filtered.filter(segment => {
      // Methods are by definition not top-level, skip them for top-level filter
      if (segment.type === 'method') return false;
      return true;
    });
  }
  
  return filtered;
}

function addSegment(node, type, name, options = {}) {
  if (!node.loc) return;

  const startLine = node.loc.start.line - 1; // Convert to 0-based
  const endLine = node.loc.end.line - 1;
  
  // Handle context preservation for methods
  let finalName = name || "anonymous";
  let parent = options.parent || null;
  let extendsClass = options.extends || null;
  
  if (type === "method" && currentContext && currentContext.PreserveContext && currentClassContext) {
    finalName = `${currentClassContext}.${finalName}`;
    parent = currentClassContext;
  }

  detectedSegments.push({
    name: finalName,
    type,
    startLine,
    endLine,
    content: "", // Will be filled later
    parent: parent,
    extends: extendsClass,
    indent: node.loc.start.column,
    selected: false,
    node: {
      type: node.type,
      start: node.start,
      end: node.end,
    },
  });
}

function parseCodeWithRegex(code) {
  // Fallback regex-based parsing (from your HTML tool)
  const patterns = [
    { regex: /class\s+(\w+)/g, type: "class" },
    { regex: /function\s+(\w+)/g, type: "function" },
    { regex: /const\s+(\w+)\s*=/g, type: "const" },
    { regex: /let\s+(\w+)\s*=/g, type: "let" },
    { regex: /var\s+(\w+)\s*=/g, type: "var" },
  ];

  const lines = code.split("\n");

  patterns.forEach(({ regex, type }) => {
    let match;
    while ((match = regex.exec(code)) !== null) {
      const startLine = code.substring(0, match.index).split("\n").length - 1;
      const endLine = findSegmentEnd(lines, startLine, 0, type);

      detectedSegments.push({
        name: match[1],
        type,
        startLine,
        endLine,
        indent: 0,
        selected: false,
      });
    }
  });
}

function findSegmentEnd(lines, startLine, baseIndent, type) {
  let braceCount = 0;
  let inSegment = false;

  for (let i = startLine; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Skip empty lines and comments
    if (!trimmed || trimmed.startsWith("//")) continue;

    // Count braces (simplified, doesn't handle strings)
    for (const char of line) {
      if (char === "{") {
        braceCount++;
        inSegment = true;
      } else if (char === "}") {
        braceCount--;
        if (inSegment && braceCount === 0) {
          return i;
        }
      }
    }

    // For arrow functions without braces
    if (type === "arrow" && !line.includes("{") && i > startLine) {
      return i;
    }
  }

  return lines.length - 1;
}

function getLineAndColumn(code, position) {
  const lines = code.substring(0, position).split("\n");
  return {
    line: lines.length,
    column: lines[lines.length - 1].length + 1,
  };
}

function showErrorContext(code, position, contextLines = 3) {
  const lines = code.split("\n");
  const { line, column } = getLineAndColumn(code, position);
  const errorLineIndex = line - 1;

  const start = Math.max(0, errorLineIndex - contextLines);
  const end = Math.min(lines.length, errorLineIndex + contextLines + 1);

  console.error(`\nError context around line ${line}, column ${column}:`);
  for (let i = start; i < end; i++) {
    const lineNum = String(i + 1).padStart(4, " ");
    const marker = i === errorLineIndex ? ">>>" : "   ";
    console.error(`${marker} ${lineNum}: ${lines[i]}`);

    if (i === errorLineIndex && column > 0) {
      const pointer = " ".repeat(column + 7) + "^";
      console.error(`    ${pointer}`);
    }
  }
}

function tryDifferentParseOptions(code, filePath) {
  const parseOptions = [
    // Try with JSX support if available
    {
      name: "module-jsx",
      options: {
        ecmaVersion: "latest",
        sourceType: "module",
        locations: true,
        allowReturnOutsideFunction: true,
        allowImportExportEverywhere: true,
        allowAwaitOutsideFunction: true,
        allowSuperOutsideMethod: true,
        allowHashBang: true,
        plugins: { jsx: true },
      },
    },
    // Try as script instead of module
    {
      name: "script",
      options: {
        ecmaVersion: "latest",
        sourceType: "script",
        locations: true,
        allowReturnOutsideFunction: true,
        allowHashBang: true,
      },
    },
    // Try older ECMAScript version
    {
      name: "es2020",
      options: {
        ecmaVersion: 2020,
        sourceType: "module",
        locations: true,
        allowReturnOutsideFunction: true,
        allowImportExportEverywhere: true,
        allowAwaitOutsideFunction: true,
        allowSuperOutsideMethod: true,
        allowHashBang: true,
      },
    },
  ];

  for (const { name, options } of parseOptions) {
    try {
      console.error(`Trying parse option: ${name}`);
      const ast = acorn.parse(code, options);
      console.error(`Success with parse option: ${name}`);
      return ast;
    } catch (error) {
      console.error(`Failed with ${name}: ${error.message}`);
    }
  }

  return null;
}

// Extract AST walking into a shared function
function walkAST(ast) {
  // Use ancestral walker to maintain context properly
  walk.ancestor(ast, {
    ClassDeclaration(node, ancestors) {
      const className = node.id ? node.id.name : "AnonymousClass";
      const extendsClass = node.superClass ? node.superClass.name : null;
      
      addSegment(node, "class", className, { extends: extendsClass });
    },
    ClassExpression(node, ancestors) {
      if (node.id) {
        const className = node.id.name;
        const extendsClass = node.superClass ? node.superClass.name : null;
        
        addSegment(node, "class", className, { extends: extendsClass });
      }
    },
    // Method definitions (will capture all methods including class methods)
    MethodDefinition(node, ancestors) {
      const methodName = node.key.name || node.key.value;
      
      // Find the parent class from ancestors
      let parentClass = null;
      for (let i = ancestors.length - 1; i >= 0; i--) {
        if (ancestors[i].type === "ClassDeclaration" || ancestors[i].type === "ClassExpression") {
          parentClass = ancestors[i].id ? ancestors[i].id.name : "AnonymousClass";
          break;
        }
      }
      
      // Handle context preservation
      let finalMethodName = methodName;
      if (currentContext && currentContext.PreserveContext && parentClass) {
        finalMethodName = `${parentClass}.${methodName}`;
      }
      
      addSegment(node, "method", finalMethodName, { parent: parentClass });
    },
    // Function declarations
    FunctionDeclaration(node, ancestors) {
      if (node.id) {
        addSegment(node, "function", node.id.name);
      }
    },
    // Function expressions (including arrow functions)
    VariableDeclarator(node, ancestors) {
      if (node.init && (node.init.type === "FunctionExpression" || node.init.type === "ArrowFunctionExpression")) {
        const type = node.init.type === "ArrowFunctionExpression" ? "arrow" : "function";
        addSegment(node, type, node.id.name);
      }
      // Handle constants
      else if (node.id && node.id.type === "Identifier") {
        // Check if this is a const declaration at module level
        let parent = null;
        for (let i = ancestors.length - 1; i >= 0; i--) {
          if (ancestors[i].type === "VariableDeclaration") {
            parent = ancestors[i];
            break;
          }
        }
        
        if (parent && parent.kind === "const") {
          const constName = node.id.name;
          
          // Filter out meaningless constants
          if (!shouldExcludeConstant(constName, currentContext)) {
            // Check if it's top-level (not inside a function)
            const isInsideFunction = ancestors.some(ancestor => 
              ancestor.type === "FunctionDeclaration" || 
              ancestor.type === "FunctionExpression" ||
              ancestor.type === "ArrowFunctionExpression"
            );
            
            if (!isInsideFunction) {
              addSegment(node, "constant", constName);
            }
          }
        }
      }
    },
    // Handle const declarations separately to ensure we catch them
    VariableDeclaration(node, ancestors) {
      if (node.kind === "const") {
        node.declarations.forEach(declarator => {
          if (declarator.id && declarator.id.type === "Identifier") {
            const constName = declarator.id.name;
            
            // Only include meaningful constants
            if (!shouldExcludeConstant(constName, currentContext)) {
              // Check if it's top-level (not inside a function)
              const isInsideFunction = ancestors.some(ancestor => 
                ancestor.type === "FunctionDeclaration" || 
                ancestor.type === "FunctionExpression" ||
                ancestor.type === "ArrowFunctionExpression"
              );
              
              if (!isInsideFunction) {
                addSegment(declarator, "constant", constName);
              }
            }
          }
        });
      }
    },
    // Object methods (but skip class methods as they're handled above)
    Property(node, ancestors) {
      // Skip if this property is inside a class (already handled)
      const isInClass = ancestors.some(ancestor => 
        ancestor.type === "ClassDeclaration" || ancestor.type === "ClassExpression"
      );
      
      if (!isInClass && node.value && (node.value.type === "FunctionExpression" || node.value.type === "ArrowFunctionExpression")) {
        const name = node.key.name || node.key.value;
        addSegment(node, "method", name);
      }
    },
    // Export declarations
    ExportNamedDeclaration(node, ancestors) {
      if (node.declaration) {
        if (node.declaration.type === "FunctionDeclaration" && node.declaration.id) {
          addSegment(node, "export", node.declaration.id.name);
        } else if (node.declaration.type === "ClassDeclaration" && node.declaration.id) {
          addSegment(node, "export", node.declaration.id.name);
        } else if (node.declaration.type === "VariableDeclaration") {
          node.declaration.declarations.forEach((decl) => {
            if (decl.id && decl.id.name) {
              addSegment(node, "export", decl.id.name);
            }
          });
        }
      } else if (node.specifiers) {
        // Handle export { name1, name2 }
        node.specifiers.forEach(spec => {
          if (spec.exported && spec.exported.name) {
            addSegment(node, "export", spec.exported.name);
          }
        });
      }
    },
    ExportDefaultDeclaration(node, ancestors) {
      addSegment(node, "export", "default");
    },
    // Global assignments (window.*, global.*, etc.)
    AssignmentExpression(node, ancestors) {
      if (node.left && node.left.type === "MemberExpression") {
        const obj = node.left.object;
        const prop = node.left.property;
        
        if (obj && prop && 
            (obj.name === "window" || obj.name === "global" || obj.name === "globalThis") &&
            prop.name) {
          addSegment(node, "global", prop.name);
        }
      }
    },
    // IIFE patterns that assign to global
    CallExpression(node, ancestors) {
      if (node.callee && node.callee.type === "FunctionExpression") {
        // Check if this IIFE contains global assignments
        const body = node.callee.body;
        if (body && body.body) {
          body.body.forEach(stmt => {
            if (stmt.type === "ExpressionStatement" && 
                stmt.expression && stmt.expression.type === "AssignmentExpression") {
              const left = stmt.expression.left;
              if (left && left.type === "MemberExpression" &&
                  left.object && left.property &&
                  (left.object.name === "window" || left.object.name === "global") &&
                  left.property.name) {
                addSegment(node, "global", left.property.name);
              }
            }
          });
        }
      }
    }
  });
}

function parseJavaScriptCode(code, filePath = "unknown", extractionContext = null) {
  detectedSegments = [];
  currentContext = extractionContext;
  currentClassContext = null;

  try {
    // Use Acorn to parse the JavaScript AST (exact logic from your HTML tool)
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

    walkAST(ast);
  } catch (error) {
    console.error(`\nAST parsing failed for file: ${filePath}`);
    console.error(`Error: ${error.message}`);

    if (error.pos !== undefined) {
      showErrorContext(code, error.pos);
    }

    console.error("\nTrying alternative parsing options...");
    const ast = tryDifferentParseOptions(code, filePath);

    if (!ast) {
      console.error(
        "All parsing options failed, falling back to regex parsing"
      );
      parseCodeWithRegex(code);
      return detectedSegments;
    } else {
      console.error("Successfully parsed with alternative options");
      walkAST(ast);
    }
  }

  // Sort segments by start line (from your HTML tool)
  detectedSegments.sort((a, b) => a.startLine - b.startLine);

  // Remove overlapping segments (keep the outer one) but preserve methods and exports
  detectedSegments = detectedSegments.filter((segment, index) => {
    for (let i = 0; i < index; i++) {
      const other = detectedSegments[i];
      if (
        segment.startLine >= other.startLine &&
        segment.endLine <= other.endLine
      ) {
        // Always preserve methods even if they're inside classes
        if (segment.type === 'method' && other.type === 'class') {
          continue; // Keep this method
        }
        // Always preserve exports even if they overlap with their underlying elements
        if (segment.type === 'export') {
          continue; // Keep this export
        }
        return false; // This segment is contained within another
      }
    }
    return true;
  });

  // Apply extraction context filtering
  detectedSegments = applyExtractionContext(detectedSegments, currentContext, code);

  return detectedSegments;
}

// Command line interface
function main() {
  if (process.argv.length < 3) {
    console.error(
      "Usage: node javascript-parser.js <file> [--extraction-context JSON] [--language-config JSON]"
    );
    process.exit(1);
  }

  const filePath = process.argv[2];
  const args = process.argv.slice(3);

  // Parse command line options
  let extractionContext = null;
  let languageConfig = null;
  let filterClass = null;
  let filterExtends = null;

  for (let i = 0; i < args.length; i += 2) {
    if (args[i] === "--extraction-context" && i + 1 < args.length) {
      try {
        extractionContext = JSON.parse(args[i + 1]);
      } catch (error) {
        console.error("Invalid extraction context JSON:", error.message);
        process.exit(1);
      }
    } else if (args[i] === "--language-config" && i + 1 < args.length) {
      try {
        languageConfig = JSON.parse(args[i + 1]);
      } catch (error) {
        console.error("Invalid language config JSON:", error.message);
        process.exit(1);
      }
    } else if (args[i] === "--filter-class" && i + 1 < args.length) {
      filterClass = args[i + 1];
    } else if (args[i] === "--filter-extends" && i + 1 < args.length) {
      filterExtends = args[i + 1];
    }
  }

  try {
    if (!fs.existsSync(filePath)) {
      console.error(`File not found: ${filePath}`);
      process.exit(1);
    }

    console.error(`Parsing file: ${filePath}`);
    const code = fs.readFileSync(filePath, "utf8");
    const segments = parseJavaScriptCode(code, filePath, extractionContext);

    // Apply legacy filters if specified (for backward compatibility)
    let filteredSegments = segments;

    if (filterClass) {
      filteredSegments = filteredSegments.filter((s) => s.name === filterClass);
    }

    if (filterExtends) {
      filteredSegments = filteredSegments.filter((s) => s.extends === filterExtends);
    }

    // Output results as JSON for PowerShell to consume
    const result = {
      filePath: filePath,
      totalSegments: segments.length,
      filteredSegments: filteredSegments.length,
      segments: filteredSegments.map((segment) => {
        // Include the actual code content for each segment
        const lines = code.split("\n");
        const content = lines
          .slice(segment.startLine, segment.endLine + 1)
          .join("\n");

        return {
          type: segment.type,
          name: segment.name,
          startLine: segment.startLine,
          endLine: segment.endLine,
          content: content,
          extends: segment.extends || undefined,
          parent: segment.parent || undefined,
          lineCount: segment.endLine - segment.startLine + 1,
        };
      }),
    };

    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error("Error parsing file:", error.message);
    process.exit(1);
  }
}

main();

// Export for module if needed
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { parseJavaScriptCode };
}