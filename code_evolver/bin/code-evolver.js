#!/usr/bin/env node

/**
 * NPM executable wrapper for code-evolver
 * Allows: npx @vibe-tools/code-evolver -ClassName MyClass
 */

const { spawn } = require('child_process');
const path = require('path');
const os = require('os');

// Get the PowerShell script path
const scriptPath = path.join(__dirname, '..', 'Track-CodeEvolution.ps1');

// Prepare arguments
const args = process.argv.slice(2);

// Determine PowerShell executable
const isWindows = os.platform() === 'win32';
const pwsh = isWindows ? 'powershell.exe' : 'pwsh';

// Build command
const pwshArgs = [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', scriptPath,
    ...args
];

// Execute
const child = spawn(pwsh, pwshArgs, {
    stdio: 'inherit',
    shell: false
});

child.on('error', (err) => {
    if (err.code === 'ENOENT') {
        console.error('PowerShell not found. Please install PowerShell Core (pwsh) or use Windows PowerShell.');
        process.exit(1);
    }
    console.error('Error running code-evolver:', err);
    process.exit(1);
});

child.on('exit', (code) => {
    process.exit(code);
});