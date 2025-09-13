#!/usr/bin/env node

// Node.js parser that uses the exact Acorn logic from js_segmenter.html
const fs = require('fs');
const path = require('path');

// Import Acorn (you'll need to install these)
const acorn = require('acorn');
const walk = require('acorn-walk');

let detectedSegments = [];

function addSegment(node, type, name) {
  if (!node.loc) return;

  const startLine = node.loc.start.line - 1; // Convert to 0-based
  const endLine = node.loc.end.line - 1;

  detectedSegments.push({
    name: name || "anonymous",
    type,
    startLine,
    endLine,
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

function parseJavaScriptCode(code, filePath = "unknown") {
  detectedSegments = [];

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

    // Walk the AST to find all relevant nodes (exact logic from your HTML tool)
    walk.simple(ast, {
      // Class declarations
      ClassDeclaration(node) {
        addSegment(node, "class", node.id ? node.id.name : "AnonymousClass");
      },
      ClassExpression(node) {
        if (node.id) {
          addSegment(node, "class", node.id.name);
        }
      },
      // Function declarations
      FunctionDeclaration(node) {
        if (node.id) {
          addSegment(node, "function", node.id.name);
        }
      },
      // Function expressions (including arrow functions)
      VariableDeclarator(node) {
        if (
          node.init &&
          (node.init.type === "FunctionExpression" ||
            node.init.type === "ArrowFunctionExpression")
        ) {
          const type =
            node.init.type === "ArrowFunctionExpression" ? "arrow" : "function";
          addSegment(node, type, node.id.name);
        }
      },
      // Object methods
      Property(node) {
        if (
          node.value &&
          (node.value.type === "FunctionExpression" ||
            node.value.type === "ArrowFunctionExpression")
        ) {
          const name = node.key.name || node.key.value;
          addSegment(node, "method", name);
        }
      },
      MethodDefinition(node) {
        const name = node.key.name || node.key.value;
        addSegment(node, "method", name);
      },
      // Export declarations
      ExportNamedDeclaration(node) {
        if (node.declaration) {
          if (
            node.declaration.type === "FunctionDeclaration" &&
            node.declaration.id
          ) {
            addSegment(node, "export", node.declaration.id.name);
          } else if (
            node.declaration.type === "ClassDeclaration" &&
            node.declaration.id
          ) {
            addSegment(node, "export", node.declaration.id.name);
          } else if (node.declaration.type === "VariableDeclaration") {
            node.declaration.declarations.forEach((decl) => {
              if (decl.id && decl.id.name) {
                addSegment(node, "export", decl.id.name);
              }
            });
          }
        }
      },
      ExportDefaultDeclaration(node) {
        addSegment(node, "export", "default");
      },
    });
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
      // Process the AST the same way as above
      walk.simple(ast, {
        ClassDeclaration(node) {
          addSegment(node, "class", node.id ? node.id.name : "AnonymousClass");
        },
        ClassExpression(node) {
          if (node.id) {
            addSegment(node, "class", node.id.name);
          }
        },
        FunctionDeclaration(node) {
          if (node.id) {
            addSegment(node, "function", node.id.name);
          }
        },
        VariableDeclarator(node) {
          if (
            node.init &&
            (node.init.type === "FunctionExpression" ||
              node.init.type === "ArrowFunctionExpression")
          ) {
            const type =
              node.init.type === "ArrowFunctionExpression"
                ? "arrow"
                : "function";
            addSegment(node, type, node.id.name);
          }
        },
        Property(node) {
          if (
            node.value &&
            (node.value.type === "FunctionExpression" ||
              node.value.type === "ArrowFunctionExpression")
          ) {
            const name = node.key.name || node.key.value;
            addSegment(node, "method", name);
          }
        },
        MethodDefinition(node) {
          const name = node.key.name || node.key.value;
          addSegment(node, "method", name);
        },
        ExportNamedDeclaration(node) {
          if (node.declaration) {
            if (
              node.declaration.type === "FunctionDeclaration" &&
              node.declaration.id
            ) {
              addSegment(node, "export", node.declaration.id.name);
            } else if (
              node.declaration.type === "ClassDeclaration" &&
              node.declaration.id
            ) {
              addSegment(node, "export", node.declaration.id.name);
            } else if (node.declaration.type === "VariableDeclaration") {
              node.declaration.declarations.forEach((decl) => {
                if (decl.id && decl.id.name) {
                  addSegment(node, "export", decl.id.name);
                }
              });
            }
          }
        },
        ExportDefaultDeclaration(node) {
          addSegment(node, "export", "default");
        },
      });
    }
  }

  // Sort segments by start line (from your HTML tool)
  detectedSegments.sort((a, b) => a.startLine - b.startLine);

  // Remove overlapping segments (keep the outer one) (from your HTML tool)
  detectedSegments = detectedSegments.filter((segment, index) => {
    for (let i = 0; i < index; i++) {
      const other = detectedSegments[i];
      if (
        segment.startLine >= other.startLine &&
        segment.endLine <= other.endLine
      ) {
        return false; // This segment is contained within another
      }
    }
    return true;
  });

  return detectedSegments;
}

// Command line interface
function main() {
  if (process.argv.length < 3) {
    console.error(
      "Usage: node acorn-parser.js <javascript-file> [--filter-class ClassName] [--filter-extends BaseClass]"
    );
    process.exit(1);
  }

  const filePath = process.argv[2];
  const args = process.argv.slice(3);

  // Parse command line options
  let filterClass = null;
  let filterExtends = null;

  for (let i = 0; i < args.length; i += 2) {
    if (args[i] === "--filter-class" && i + 1 < args.length) {
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
    const segments = parseJavaScriptCode(code, filePath);

    // Apply filters if specified
    let filteredSegments = segments;

    if (filterClass) {
      filteredSegments = filteredSegments.filter((s) => s.name === filterClass);
    }

    if (filterExtends) {
      // For this we'd need to analyze the actual AST nodes to find inheritance
      // For now, just check if the code contains "extends {filterExtends}"
      filteredSegments = filteredSegments.filter((s) => {
        if (s.type !== "class") return false;
        const lines = code.split("\n");
        const classLine = lines[s.startLine];
        return classLine && classLine.includes(`extends ${filterExtends}`);
      });
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
          ...segment,
          content: content,
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
