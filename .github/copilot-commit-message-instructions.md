# Generate a commit message that identifies specific code elements that changed.

## Format:
```
<type>(<filename>): <summary under 50 chars>

[<exact function/class/const name>] <ACTION>: <what changed>
```

## Rules:
- Components are ONLY: function names, class names, const/let/var names, PowerShell function names
- Use the EXACT name from code (e.g., Get-CompressedDiff, not "compressed diff function")
- For CSS/HTML changes, list the modified functions that generate them, NOT the CSS itself
- ACTION must be: NEW|MODIFIED|REMOVED|RENAMED|MOVED
- If only CSS/styling changed with no function changes, just use the first line
- Branch context: Use current git branch

## Example for PowerShell:
```
feat(Track-CodeEvolution): Add NeonSurge theme

[Export-HtmlReport] MODIFIED: Updated CSS color variables to NeonSurge palette
[Get-CompressedDiffStyles] NEW: Added function to generate theme-specific styles
[toggleCode] MODIFIED: Added animation class for theme transitions
```

## Example for CSS-only changes:
```
style(Track-CodeEvolution): Update UI to NeonSurge theme
```
(no component list needed if no functions changed)

## Instructions:
1. Analyze the staged changes using `git diff --staged` in @workspace
2. Identify the primary file changed for the scope
3. Extract EXACT function/class/const names from the code
4. Determine the ACTION for each component
5. Write concise descriptions of what changed

Generate the commit message for the current staged changes in @workspace.