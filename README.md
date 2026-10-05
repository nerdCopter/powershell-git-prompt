# PowerShell prompt

Git-aware prompt for Windows PowerShell 5.1 (legacy) and PowerShell 7+ (modern, pwsh).

Prompt layout:

```
branch...upstream [ahead N] [behind N] (sha) [M:s/u A:s/u D:s/u S:n]
 HOSTNAME current\path >
```

`M`, `A`, `D` are staged/unstaged counts for modified, added, deleted files. `S` is the stash count.

## Windows PowerShell 5.1 (legacy)

Profile: `$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`

- Helpers: `x` (exit), `st` (Sublime Text), `gl [n]` (short git log), `gs` (`git status -sb`), `push` (`git push`).
- Loads the git prompt:

```powershell
$gitPromptFile = "$env:USERPROFILE\Documents\WindowsPowerShell\git-prompt.ps1"
if (Test-Path $gitPromptFile -PathType Leaf) {
    . $gitPromptFile
}
```

- Defines `prompt`, which calls `Write-ColorizedGitPrompt (Get-GitPrompt)`, then prints the hostname and current path.

## PowerShell 7+ (modern, pwsh)

Stub: `$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` (outside this repo)

It only sources the 5.1 profile above, so both shells share one prompt:

```powershell
####################################
echo "### User profile for PWSH 6 and above"
####################################


# just source the 5.x profile
$legacyProfile = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
if (Test-Path $legacyProfile) {
    . $legacyProfile
}
```

## git-prompt.ps1

Path: `$env:USERPROFILE\Documents\WindowsPowerShell\git-prompt.ps1`. Prints `### git prompt` when loaded.

| Function | Purpose |
|---|---|
| `Resolve-GitPromptExe` | Picks the real `mingw64\bin\git.exe` of the installed Git for Windows instead of the `cmd\git.exe` launcher; falls back to `git` on PATH. Result is stored in `$global:GitPromptExe`. |
| `Get-GitPromptCommonDir` | Finds the repo by walking up for `.git` (worktrees and submodules supported). No git process is started outside a repo. |
| `Get-GitPrompt` | Runs one `git status --porcelain=v2 --branch --untracked-files=no` and builds the prompt text. Short SHA is the first 7 characters of `branch.oid`. Stash count is the line count of `logs\refs\stash` (falls back to `git rev-list --walk-reflogs --count refs/stash` for reftable repos). |
| `Write-ColorizedGitPrompt` | Prints the prompt text with colors: branch cyan, ahead green, behind red, SHA gray, staged green, unstaged red, stash green at 0 and red above 0. |