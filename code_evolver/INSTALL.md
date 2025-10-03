# Installation Patterns for Code Evolver

## Method 1: Global Installation (Recommended)
Install once, use anywhere on your system:

```powershell
# Install with PATH integration
.\Install-GlobalTool.ps1 -AddToPath -CreateAlias

# Then from any project:
code-evolver -ClassName MyClass -ExportHtml
```

## Method 2: NPM Package (For JS Projects)
```bash
# Install globally
npm install -g @vibe-tools/code-evolver

# Or as dev dependency
npm install --save-dev @vibe-tools/code-evolver

# Use via npx
npx code-evolver -ClassName MyClass
```

## Method 3: Git Submodule (Version Control)
Add as a submodule to your project:

```bash
# Add as submodule
git submodule add https://github.com/yourusername/vibe_tools.git tools/vibe_tools
git submodule update --init

# Create project wrapper
cat > track-evolution.ps1 << 'EOF'
param([Parameter(ValueFromRemainingArguments)]$args)
& ".\tools\vibe_tools\code_evolver\Track-CodeEvolution.ps1" @args
EOF

# Use in your project
.\track-evolution.ps1 -ClassName MyClass
```

## Method 4: Project Copy Script (Simple)
Copy just what you need into your project:

```powershell
# Run from vibe_tools
.\code_evolver\Export-ToProject.ps1 -TargetProject "C:\MyProject"

# Creates: C:\MyProject\.tools\code-evolver\
# Use: .\.tools\code-evolver\run.ps1 -ClassName MyClass
```

## Method 5: Chocolatey Package (Windows)
```powershell
# Future: Install via Chocolatey
choco install code-evolver

# Use globally
code-evolver -ClassName MyClass
```

## Quick Start Without Installation
Clone and run directly:

```bash
# Clone somewhere permanent
git clone https://github.com/yourusername/vibe_tools.git ~/tools/vibe_tools

# Run from any project
~/tools/vibe_tools/code_evolver/Track-CodeEvolution.ps1 -ClassName MyClass

# Or create an alias in your shell profile
alias code-evolver='powershell.exe -ExecutionPolicy Bypass -File ~/tools/vibe_tools/code_evolver/Track-CodeEvolution.ps1'
```