######################
Write-Host "### git prompt" -ForegroundColor Green
######################

# AI-assisted rewrite: one git process per prompt, stash count and repo detection via file I/O.
# Output format is unchanged: "branch...upstream [ahead X] [behind Y] (sha) [M:s/u A:s/u D:s/u S:n]"

function Resolve-GitPromptExe {
    # Prefer the real git.exe inside the installed Git for Windows over the cmd\git.exe launcher
    # (the launcher spawns the real binary as a second process on every call).
    $cmd = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    $exe = $cmd.Source
    $exeDir = Split-Path $exe -Parent
    if ((Split-Path $exeDir -Leaf) -ieq 'cmd') {
        $gitRoot = Split-Path $exeDir -Parent
        foreach ($sub in 'mingw64', 'clangarm64', 'mingw32') {
            $real = Join-Path $gitRoot "$sub\bin\git.exe"
            if ([IO.File]::Exists($real)) { return $real }
        }
    }
    return $exe
}

$global:GitPromptExe = Resolve-GitPromptExe

function Get-GitPromptCommonDir {
    # Locate the repository's common git dir without starting git. Returns $null outside a repo.
    $loc = Get-Location
    if ($loc.Provider.Name -ne 'FileSystem') { return $null }
    $d = [IO.DirectoryInfo]$loc.ProviderPath
    while ($d) {
        $dotGit = [IO.Path]::Combine($d.FullName, '.git')
        $gitDir = $null
        if ([IO.Directory]::Exists($dotGit)) {
            $gitDir = $dotGit
        } elseif ([IO.File]::Exists($dotGit)) {
            # Worktree or submodule: ".git" is a file containing "gitdir: <path>"
            $first = [IO.File]::ReadLines($dotGit) | Select-Object -First 1
            if ($first -match '^gitdir:\s*(.+)$') {
                $gitDir = [IO.Path]::GetFullPath([IO.Path]::Combine($d.FullName, $matches[1].Trim()))
            }
        }
        if ($gitDir) {
            $commonFile = [IO.Path]::Combine($gitDir, 'commondir')
            if ([IO.File]::Exists($commonFile)) {
                $rel = ([IO.File]::ReadAllText($commonFile)).Trim()
                return [IO.Path]::GetFullPath([IO.Path]::Combine($gitDir, $rel))
            }
            return $gitDir
        }
        $d = $d.Parent
    }
    return $null
}

function Get-GitPrompt {
    $commonDir = Get-GitPromptCommonDir
    if (-not $commonDir -or -not $global:GitPromptExe) {
        return ""
    }

    $lines = @(& $global:GitPromptExe --no-optional-locks status --porcelain=v2 --branch --untracked-files=no 2>$null)
    if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) {
        return ""
    }

    $oid = ""
    $branch = ""
    $upstream = ""
    $ahead = 0
    $behind = 0
    $stagedMod = 0
    $unstagedMod = 0
    $stagedAdd = 0
    $unstagedAdd = 0
    $stagedDel = 0
    $unstagedDel = 0

    foreach ($line in $lines) {
        if ($line.Length -lt 4) { continue }
        if ($line[0] -eq '#') {
            if ($line.StartsWith('# branch.oid ')) { $oid = $line.Substring(13) }
            elseif ($line.StartsWith('# branch.head ')) { $branch = $line.Substring(14) }
            elseif ($line.StartsWith('# branch.upstream ')) { $upstream = $line.Substring(18) }
            elseif ($line.StartsWith('# branch.ab ')) {
                $ab = $line.Substring(12) -split ' '
                $ahead = [int]$ab[0].TrimStart('+')
                $behind = [int]$ab[1].TrimStart('-')
            }
        }
        elseif ($line[1] -eq ' ' -and ($line[0] -eq '1' -or $line[0] -eq '2' -or $line[0] -eq 'u')) {
            # "." means unchanged in porcelain v2
            $col1 = $line[2]
            $col2 = $line[3]

            if ($col1 -eq 'M') { $stagedMod++ }
            if ($col2 -eq 'M') { $unstagedMod++ }
            if ($col1 -eq 'M' -and $col2 -eq 'M') { $unstagedMod-- }

            if ($col1 -eq 'A') { $stagedAdd++ }
            if ($col2 -eq 'A') { $unstagedAdd++ }

            if ($col1 -eq 'D') { $stagedDel++ }
            if ($col2 -eq 'D') { $unstagedDel++ }
        }
    }

    # "(initial)" is reported before the first commit
    $sha = if ($oid.Length -ge 7 -and $oid -ne '(initial)') { $oid.Substring(0, 7) } else { "initial" }

    $branchStatus = $branch
    if ($upstream) {
        $branchStatus = "${branch}...${upstream}"
        if ($ahead -gt 0) { $branchStatus += " [ahead $ahead]" }
        if ($behind -gt 0) { $branchStatus += " [behind $behind]" }
    }
    $branchStatus += " (${sha})"

    # Stash count = number of reflog entries for refs/stash (no git process needed)
    $stashCount = 0
    $stashLog = [IO.Path]::Combine($commonDir, 'logs', 'refs', 'stash')
    if ([IO.File]::Exists($stashLog)) {
        $stashCount = [IO.File]::ReadAllLines($stashLog).Length
    }
    elseif ([IO.Directory]::Exists([IO.Path]::Combine($commonDir, 'reftable'))) {
        $n = & $global:GitPromptExe rev-list --walk-reflogs --count refs/stash 2>$null
        if ($n) { $stashCount = [int]$n }
    }

    $mod = "M:$stagedMod/$unstagedMod"
    $add = "A:$stagedAdd/$unstagedAdd"
    $del = "D:$stagedDel/$unstagedDel"
    $stash = "S:$stashCount"

    return "${branchStatus} [${mod} ${add} ${del} ${stash}]"
}
function Write-ColorizedGitPrompt {
    # Parse and colorize the git prompt output from Get-GitPrompt
    # Format: "branch...upstream [ahead X] [behind Y] (sha) [M:s/u A:s/u D:s/u S:count]"
    param(
        [string]$promptStr
    )
    
    if (-not $promptStr) {
        return
    }

    Write-Host ""
    
    # Parse the prompt string with optional ahead/behind sections
    # Matches: "branch" or "branch...upstream" optionally followed by "[ahead X]" and/or "[behind Y]" and "(sha)" and "[stats]"
    if ($promptStr -match '^(?<branch>[^\s\[]+)(?:\s\[(?<ahead>ahead\s+\d+)\])?(?:\s\[(?<behind>behind\s+\d+)\])?\s\((?<sha>[^\)]+)\)\s\[(?<stats>.+)\]$') {
        $branch = $matches['branch']
        $ahead = $matches['ahead']
        $behind = $matches['behind']
        $sha = $matches['sha']
        $stats = $matches['stats']
        
        # 1. Branch (Cyan)
        Write-Host $branch -ForegroundColor Cyan -NoNewline
        
        # 2. Sync Status (Green/Red)
        if ($ahead) {
            Write-Host " [$ahead]" -ForegroundColor Green -NoNewline
        }
        if ($behind) {
            Write-Host " [$behind]" -ForegroundColor Red -NoNewline
        }
        
        # 3. SHA (Gray)
        Write-Host " ($sha)" -ForegroundColor Gray -NoNewline
        
        # 4. Status counts
        Write-Host " [" -NoNewline
        
        # Parse stats: "M:s/u A:s/u D:s/u S:count"
        foreach ($stat in $stats -split '\s+') {
            if ($stat -match '^([MAD]):(\d+)/(\d+)$') {
                $type = $matches[1]
                $staged = $matches[2]
                $unstaged = $matches[3]
                Write-Host "${type}:" -NoNewline
                Write-Host $staged -ForegroundColor Green -NoNewline
                Write-Host "/$unstaged" -ForegroundColor Red -NoNewline
                Write-Host " " -NoNewline
            } elseif ($stat -match '^S:(\d+)$') {
                $count = $matches[1]
                $stashColor = if ($count -gt 0) { 'Red' } else { 'Green' }
                Write-Host "S:" -NoNewline
                Write-Host $count -ForegroundColor $stashColor -NoNewline
                Write-Host " " -NoNewline
            }
        }
        Write-Host "]" -NoNewline
    }
    else {
        Write-Host "Parse Error: $promptStr" -ForegroundColor Red -NoNewline
    }
}