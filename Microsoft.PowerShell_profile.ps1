########################
echo "### User profile"
########################



function x { exit }

function st { & "C:\Program Files\Sublime Text\sublime_text.exe" @args }

del alias:gl -Force -ErrorAction SilentlyContinue
function gl { 
    param(
        [int]$Count = 5 
    )
    git log --pretty=format:"%h %ad %s" --date=short | Select-Object -First $Count 
}

function gs { git status -sb }

function push { git push }


# --- PROGRAMMATIC SOURCING FOR GIT PROMPT ---
$gitPromptFile = "$env:USERPROFILE\Documents\WindowsPowerShell\git-prompt.ps1"
if (Test-Path $gitPromptFile -PathType Leaf) {
    . $gitPromptFile
}


function prompt {
    $hostname = $env:COMPUTERNAME
    $drive = Get-Location
    $NL = "$([char]10)"

    #Write-Host "${NL}"
    Write-ColorizedGitPrompt (Get-GitPrompt)
    Write-Host "${NL} ${hostname} ${drive}" -ForegroundColor Yellow -NoNewline
    return " > "
}
