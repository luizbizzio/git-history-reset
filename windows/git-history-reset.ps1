[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "$env:USERPROFILE\git-history-reset-workspace",
    [string]$InstallRoot = "$env:LOCALAPPDATA\Programs\git-history-reset",
    [string]$BinRoot = "$env:USERPROFILE\bin",
    [string]$Message = "Initial commit",
    [string]$Filter,
    [string]$SourceUrl,
    [Alias('Update')]
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$PushForce,
    [switch]$Sign,
    [switch]$NoSign,
    [switch]$RemoveCloneOnSuccess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:SelfPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.PSCommandPath }

if (-not $script:SelfPath) {
    throw "Could not determine the current script path."
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "[>] $Text" -ForegroundColor Cyan
}

function Write-InfoLine {
    param([string]$Label, [string]$Value)
    Write-Host ("  {0,-18} {1}" -f $Label, $Value) -ForegroundColor Gray
}

function Write-WarnLine {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

function Write-ErrorLine {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Red
}

function Write-SuccessLine {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Green
}

function Write-StepLine {
    param([string]$Text)
    Write-Host ("  - {0}" -f $Text) -ForegroundColor DarkGray
}

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$FallbackPaths = @()
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    foreach ($candidate in $FallbackPaths) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Invoke-ToolCaptured {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Args,
        [switch]$AllowFailure,
        [switch]$NoOutput
    )

    $output = & $Path @Args 2>&1
    $exitCode = $LASTEXITCODE

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $message = (@($output) -join [Environment]::NewLine).Trim()
        if (-not $message) {
            $message = "$Path $($Args -join ' ') failed."
        }
        throw $message
    }

    if ($NoOutput) {
        return $null
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Invoke-ToolLive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Args,
        [switch]$AllowFailure
    )

    & $Path @Args
    $exitCode = $LASTEXITCODE

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$Path $($Args -join ' ') failed with exit code $exitCode."
    }

    return $exitCode
}

function Get-TrimmedOutput {
    param([Parameter(Mandatory = $true)]$Result)
    return (($Result.Output -join "`n").Trim())
}

function Convert-JsonTextToArray {
    param([Parameter(Mandatory = $true)][string]$JsonText)

    $trimmed = $JsonText.Trim()
    if (-not $trimmed) {
        return @()
    }

    $parsed = $trimmed | ConvertFrom-Json
    if ($null -eq $parsed) {
        return @()
    }

    if ($parsed -is [System.Array]) {
        return @($parsed)
    }

    if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
        return @($parsed)
    }

    return @($parsed)
}

function Get-UserPathEntries {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) {
        return @()
    }
    return @($current.Split(';') | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}

function Add-UserPathEntry {
    param([Parameter(Mandatory = $true)][string]$Entry)

    $normalizedTarget = [System.IO.Path]::GetFullPath($Entry).TrimEnd('\\')
    $entries = Get-UserPathEntries
    foreach ($existing in $entries) {
        $normalizedExisting = [System.IO.Path]::GetFullPath($existing).TrimEnd('\\')
        if ($normalizedExisting -ieq $normalizedTarget) {
            return $false
        }
    }

    $newEntries = @($entries + $Entry)
    [Environment]::SetEnvironmentVariable('Path', ($newEntries -join ';'), 'User')
    return $true
}

function Remove-UserPathEntry {
    param([Parameter(Mandatory = $true)][string]$Entry)

    $normalizedTarget = [System.IO.Path]::GetFullPath($Entry).TrimEnd('\\')
    $entries = Get-UserPathEntries
    $kept = New-Object System.Collections.Generic.List[string]
    $removed = $false

    foreach ($existing in $entries) {
        $normalizedExisting = [System.IO.Path]::GetFullPath($existing).TrimEnd('\\')
        if ($normalizedExisting -ieq $normalizedTarget) {
            $removed = $true
        }
        else {
            $kept.Add($existing)
        }
    }

    if ($removed) {
        [Environment]::SetEnvironmentVariable('Path', ($kept.ToArray() -join ';'), 'User')
    }

    return $removed
}

function Remove-SessionPathEntry {
    param([Parameter(Mandatory = $true)][string]$Entry)

    $normalizedTarget = [System.IO.Path]::GetFullPath($Entry).TrimEnd('\\')
    $sessionEntries = @($env:Path -split ';' | Where-Object { $_ -and $_.Trim().Length -gt 0 })
    $kept = New-Object System.Collections.Generic.List[string]

    foreach ($existing in $sessionEntries) {
        $normalizedExisting = [System.IO.Path]::GetFullPath($existing).TrimEnd('\\')
        if ($normalizedExisting -ine $normalizedTarget) {
            $kept.Add($existing)
        }
    }

    $env:Path = ($kept.ToArray() -join ';')
}

function New-CmdShimContent {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    $escapedScript = $ScriptPath.Replace('%', '%%')
    return @"
@echo off
setlocal
set "SCRIPT=$escapedScript"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
"@
}

function Install-Self {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRootPath,
        [Parameter(Mandatory = $true)][string]$BinRootPath,
        [string]$DownloadUrl
    )

    $currentScriptPath = $script:SelfPath
    if (-not $currentScriptPath -or -not (Test-Path $currentScriptPath)) {
        throw "This script must run from a file to install itself."
    }

    $installRootFull = [System.IO.Path]::GetFullPath($InstallRootPath)
    $binRootFull = [System.IO.Path]::GetFullPath($BinRootPath)
    $targetScriptPath = Join-Path $installRootFull 'git-history-reset.ps1'
    $shimPath = Join-Path $binRootFull 'git-history-reset.cmd'
    $aliasShimPath = Join-Path $binRootFull 'ghr.cmd'
    $sourceUrlFile = Join-Path $installRootFull 'source-url.txt'

    New-Item -ItemType Directory -Path $installRootFull -Force | Out-Null
    New-Item -ItemType Directory -Path $binRootFull -Force | Out-Null

    $effectiveSourceUrl = $DownloadUrl
    if (-not $effectiveSourceUrl -and (Test-Path $sourceUrlFile)) {
        $effectiveSourceUrl = (Get-Content -Path $sourceUrlFile -Raw).Trim()
    }

    if ($effectiveSourceUrl) {
        Write-Section "Installing script"
        Write-InfoLine 'Source URL' $effectiveSourceUrl
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ('git-history-reset-' + [Guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Invoke-WebRequest -Uri $effectiveSourceUrl -OutFile $tempFile -UseBasicParsing
            Copy-Item -Path $tempFile -Destination $targetScriptPath -Force
        }
        finally {
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        Set-Content -Path $sourceUrlFile -Value $effectiveSourceUrl -Encoding UTF8
    }
    else {
        Write-Section "Installing script"
        Write-InfoLine 'Source file' $currentScriptPath
        $sourceFull = [System.IO.Path]::GetFullPath($currentScriptPath)
        $targetFull = [System.IO.Path]::GetFullPath($targetScriptPath)
        if ($sourceFull -ine $targetFull) {
            Copy-Item -Path $currentScriptPath -Destination $targetScriptPath -Force
        }
    }

    $shimContent = New-CmdShimContent -ScriptPath $targetScriptPath
    Set-Content -Path $shimPath -Value $shimContent -Encoding ASCII
    Set-Content -Path $aliasShimPath -Value $shimContent -Encoding ASCII

    $pathChanged = Add-UserPathEntry -Entry $binRootFull

    if ($env:Path -notmatch [regex]::Escape($binRootFull)) {
        $env:Path = $binRootFull + ';' + $env:Path
    }

    Write-SuccessLine "Installation completed."
    Write-InfoLine 'Script path' $targetScriptPath
    Write-InfoLine 'Launcher' $shimPath
    Write-InfoLine 'Alias' $aliasShimPath
    if ($pathChanged) {
        Write-WarnLine "A new terminal may still be required for PATH-based usage in your current shell."
    }
    else {
        Write-SuccessLine "'git-history-reset' and 'ghr' are already available through your user PATH."
    }

    Write-Host ""
    Write-Host "Run now in this session:" -ForegroundColor Cyan
    Write-Host ('  CMD        set "PATH={0};%%PATH%%" && ghr' -f $binRootFull) -ForegroundColor Gray
    Write-Host ('  PowerShell $env:Path = "{0};$env:Path"; ghr' -f $binRootFull) -ForegroundColor Gray
    Write-Host ('  Direct     "{0}"' -f $aliasShimPath) -ForegroundColor Gray

    return [pscustomobject]@{
        ScriptPath = $targetScriptPath
        ShimPath = $shimPath
        AliasShimPath = $aliasShimPath
        PathChanged = $pathChanged
    }
}

function Uninstall-Self {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRootPath,
        [Parameter(Mandatory = $true)][string]$BinRootPath
    )

    $installRootFull = [System.IO.Path]::GetFullPath($InstallRootPath)
    $binRootFull = [System.IO.Path]::GetFullPath($BinRootPath)
    $shimPath = Join-Path $binRootFull 'git-history-reset.cmd'
    $aliasShimPath = Join-Path $binRootFull 'ghr.cmd'

    Write-Section "Uninstalling"

    $pathRemoved = Remove-UserPathEntry -Entry $binRootFull
    Remove-SessionPathEntry -Entry $binRootFull
    if ($pathRemoved) {
        Write-SuccessLine "User PATH entry removed."
    }

    $currentScriptPath = $script:SelfPath
    $installedScriptPath = Join-Path $installRootFull 'git-history-reset.ps1'
    $isRunningInstalledCopy = $false
    if ($currentScriptPath -and (Test-Path $installedScriptPath)) {
        $isRunningInstalledCopy = ([System.IO.Path]::GetFullPath($currentScriptPath) -ieq [System.IO.Path]::GetFullPath($installedScriptPath))
    }

    $quotedShim = '"' + $shimPath.Replace('"', '""') + '"'
    $quotedAlias = '"' + $aliasShimPath.Replace('"', '""') + '"'
    $quotedBin = '"' + $binRootFull.Replace('"', '""') + '"'
    $quotedInstall = '"' + $installRootFull.Replace('"', '""') + '"'

    if (-not (Test-Path $shimPath)) {
        Write-WarnLine "Launcher was not found."
    }
    if (-not (Test-Path $aliasShimPath)) {
        Write-WarnLine "Alias was not found."
    }

    $cleanupParts = @()
    $cleanupParts += "del /f /q $quotedShim 2>nul"
    $cleanupParts += "del /f /q $quotedAlias 2>nul"
    $cleanupParts += "rmdir $quotedBin 2>nul"

    if ($isRunningInstalledCopy) {
        $cleanupParts += "rmdir /s /q $quotedInstall 2>nul"
        Write-SuccessLine "Installed files scheduled for removal."
    }
    elseif (Test-Path $installRootFull) {
        Remove-Item -Path $installRootFull -Recurse -Force -ErrorAction SilentlyContinue
        Write-SuccessLine "Installed files removed."
    }
    else {
        Write-WarnLine "Install directory was not found."
    }

    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "ping 127.0.0.1 -n 3 > nul & " + ($cleanupParts -join ' & ')) -WindowStyle Hidden
    Write-SuccessLine "Launcher cleanup scheduled."

    Write-SuccessLine "Uninstall completed."
}

function Ensure-GitHubCli {
    param([Parameter(Mandatory = $true)][string[]]$FallbackPaths)

    $ghPath = Resolve-ToolPath -Name 'gh' -FallbackPaths $FallbackPaths
    if ($ghPath) {
        return $ghPath
    }

    Write-WarnLine "GitHub CLI (gh) is required to list repositories, including private ones."
    $installAnswer = Read-Host "Install GitHub CLI now? [Y/N]"
    if ($installAnswer -notmatch '^(y|yes)$') {
        throw "GitHub CLI is required. Operation cancelled."
    }

    $wingetPath = Resolve-ToolPath -Name 'winget'
    if (-not $wingetPath) {
        Write-WarnLine "WinGet is not available on this machine."
        Write-WarnLine "The official GitHub CLI install page will be opened in your browser."
        Start-Process 'https://cli.github.com/'
        throw "Install GitHub CLI from the official page, then run the script again."
    }

    Write-Section "Installing GitHub CLI"
    & $wingetPath install --id GitHub.cli --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI installation via WinGet failed."
    }

    $ghPath = Resolve-ToolPath -Name 'gh' -FallbackPaths $FallbackPaths
    if (-not $ghPath) {
        throw "GitHub CLI appears to be installed, but this terminal still cannot find gh. Open a new terminal window and run the script again."
    }

    Write-SuccessLine "GitHub CLI installed successfully."
    return $ghPath
}

function Ensure-GitHubAuth {
    param([Parameter(Mandatory = $true)][string]$GhPath)

    Write-Section "Checking GitHub authentication"
    $status = Invoke-ToolCaptured -Path $GhPath -Args @('auth', 'status', '--active') -AllowFailure
    if ($status.ExitCode -eq 0) {
        Write-SuccessLine "GitHub authentication is active."
        return
    }

    Write-WarnLine "GitHub CLI is installed but not authenticated."
    Write-WarnLine "A browser-based GitHub login will start now."
    $null = Invoke-ToolCaptured -Path $GhPath -Args @('auth', 'login', '--web', '--git-protocol', 'https') -NoOutput

    $status = Invoke-ToolCaptured -Path $GhPath -Args @('auth', 'status', '--active') -AllowFailure
    if ($status.ExitCode -ne 0) {
        throw "Authentication did not complete successfully."
    }

    Write-SuccessLine "GitHub authentication is active."
}

function Get-AuthenticatedLogin {
    param([Parameter(Mandatory = $true)][string]$GhPath)

    $result = Invoke-ToolCaptured -Path $GhPath -Args @('api', 'user', '--jq', '.login')
    $login = ($result.Output -join "`n").Trim()
    if (-not $login) {
        throw "Could not determine the authenticated GitHub account."
    }
    return $login
}

function Get-OwnedRepos {
    param(
        [Parameter(Mandatory = $true)][string]$GhPath,
        [Parameter(Mandatory = $true)][string]$Login
    )

    $result = Invoke-ToolCaptured -Path $GhPath -Args @(
        'repo', 'list', $Login,
        '--limit', '1000',
        '--json', 'name,nameWithOwner,isPrivate,defaultBranchRef,isFork,updatedAt,url,visibility'
    )

    $jsonText = ($result.Output -join "`n")
    $repos = Convert-JsonTextToArray -JsonText $jsonText | Sort-Object nameWithOwner
    return @($repos)
}

function Show-RepoTable {
    param([Parameter(Mandatory = $true)][object[]]$Repos)

    Write-Host ""
    Write-Host "Available repositories" -ForegroundColor Cyan
    Write-Host ""

    $nameWidth = 44
    $visWidth = 9
    $branchWidth = 14
    $kindWidth = 8
    $updatedWidth = 10

    $header = ("{0,3}  {1,-$nameWidth}  {2,-$visWidth}  {3,-$branchWidth}  {4,-$kindWidth}  {5,-$updatedWidth}" -f '#', 'Repository', 'Visibility', 'Branch', 'Kind', 'Updated')
    Write-Host $header -ForegroundColor White
    Write-Host ("{0,3}  {1,-$nameWidth}  {2,-$visWidth}  {3,-$branchWidth}  {4,-$kindWidth}  {5,-$updatedWidth}" -f ('---'), ('-' * $nameWidth), ('-' * $visWidth), ('-' * $branchWidth), ('-' * $kindWidth), ('-' * $updatedWidth)) -ForegroundColor DarkGray

    for ($i = 0; $i -lt $Repos.Count; $i++) {
        $repo = $Repos[$i]

        $name = [string]$repo.nameWithOwner
        if (-not $name) {
            $name = [string]$repo.name
        }
        if (-not $name) {
            $name = '-'
        }
        if ($name.Length -gt $nameWidth) {
            $name = $name.Substring(0, $nameWidth - 3) + '...'
        }

        $visibility = '-'
        if ($repo.visibility) {
            $visibility = [string]$repo.visibility
        }
        elseif ($repo.isPrivate) {
            $visibility = 'private'
        }
        else {
            $visibility = 'public'
        }

        $branch = '-'
        if ($repo.defaultBranchRef -and $repo.defaultBranchRef.name) {
            $branch = [string]$repo.defaultBranchRef.name
        }
        if ($branch.Length -gt $branchWidth) {
            $branch = $branch.Substring(0, $branchWidth - 3) + '...'
        }

        $kind = if ($repo.isFork) { 'fork' } else { 'source' }

        $updated = '-'
        if ($repo.updatedAt) {
            try {
                $updated = ([DateTime]$repo.updatedAt).ToString('yyyy-MM-dd')
            }
            catch {
                $updated = [string]$repo.updatedAt
            }
        }

        $line = ("{0,3}  {1,-$nameWidth}  {2,-$visWidth}  {3,-$branchWidth}  {4,-$kindWidth}  {5,-$updatedWidth}" -f ($i + 1), $name, $visibility, $branch, $kind, $updated)
        $color = if ($repo.isPrivate) { 'Yellow' } else { 'Gray' }
        Write-Host $line -ForegroundColor $color
    }
}

function Read-RepoSelection {
    param([Parameter(Mandatory = $true)][int]$Max)

    while ($true) {
        Write-Host ""
        $raw = Read-Host "Select the repository number"
        $selected = 0
        if ([int]::TryParse($raw, [ref]$selected)) {
            if ($selected -ge 1 -and $selected -le $Max) {
                return $selected
            }
        }
        Write-WarnLine "Please enter a valid number between 1 and $Max."
    }
}

function With-GitPromptDisabled {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    $oldGitPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        & $Action
    }
    finally {
        if ($null -eq $oldGitPrompt) {
            Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        }
        else {
            $env:GIT_TERMINAL_PROMPT = $oldGitPrompt
        }
    }
}

function Try-CreateCommit {
    param(
        [Parameter(Mandatory = $true)][string]$GitPath,
        [Parameter(Mandatory = $true)][string[]]$CommitArgs
    )

    $attempt1 = Invoke-ToolCaptured -Path $GitPath -Args $CommitArgs -AllowFailure
    if ($attempt1.ExitCode -eq 0) {
        return
    }

    $text1 = Get-TrimmedOutput -Result $attempt1
    $looksLikeGpg = $text1 -match 'gpg failed to sign the data' -or $text1 -match 'failed to write commit object' -or $text1 -match 'gpg-agent'
    if (-not $looksLikeGpg) {
        if (-not $text1) {
            $text1 = "$GitPath $($CommitArgs -join ' ') failed."
        }
        throw $text1
    }

    Write-WarnLine "Commit signing failed on the first attempt. Retrying once after a short delay."
    Start-Sleep -Seconds 2

    $attempt2 = Invoke-ToolCaptured -Path $GitPath -Args $CommitArgs -AllowFailure
    if ($attempt2.ExitCode -eq 0) {
        Write-SuccessLine "Commit succeeded on retry."
        return
    }

    $text2 = Get-TrimmedOutput -Result $attempt2
    if (-not $text2) {
        $text2 = "$GitPath $($CommitArgs -join ' ') failed."
    }
    throw $text2
}

$originalLocation = (Get-Location).Path

try {
    if ($Install -and $Uninstall) {
        throw "Use either -Install or -Uninstall, not both."
    }
    if ($Sign -and $NoSign) {
        throw "Use either -Sign or -NoSign, not both."
    }

    if ($Install) {
        $null = Install-Self -InstallRootPath $InstallRoot -BinRootPath $BinRoot -DownloadUrl $SourceUrl
        exit 0
    }

    if ($Uninstall) {
        Uninstall-Self -InstallRootPath $InstallRoot -BinRootPath $BinRoot
        exit 0
    }

    Write-Section "Checking tools"

    $gitPath = Resolve-ToolPath -Name 'git'
    if (-not $gitPath) {
        throw "Git is required but was not found in PATH. Install Git first."
    }

    $ghFallbacks = @(
        'C:\Program Files\GitHub CLI\gh.exe',
        'C:\Program Files (x86)\GitHub CLI\gh.exe'
    )

    $ghPath = Ensure-GitHubCli -FallbackPaths $ghFallbacks
    Ensure-GitHubAuth -GhPath $ghPath

    Write-Section "Configuring git credentials"
    $setupGit = Invoke-ToolCaptured -Path $ghPath -Args @('auth', 'setup-git') -AllowFailure
    if ($setupGit.ExitCode -eq 0) {
        Write-SuccessLine "git is configured to use GitHub CLI credentials."
    }
    else {
        Write-WarnLine "Could not configure git credentials automatically. Clone and push may still work depending on your environment."
    }

    Write-Section "Reading authenticated GitHub account"
    $login = Get-AuthenticatedLogin -GhPath $ghPath
    Write-InfoLine 'GitHub account' $login

    Write-Section "Fetching repositories"
    $repos = @(Get-OwnedRepos -GhPath $ghPath -Login $login)
    if ($repos.Count -eq 0) {
        throw "No repositories were returned for the authenticated account."
    }

    if ($Filter) {
        $filtered = @($repos | Where-Object { $_.nameWithOwner -like "*$Filter*" -or $_.name -like "*$Filter*" })
        if ($filtered.Count -eq 0) {
            throw "No repositories matched filter '$Filter'."
        }
        $repos = $filtered
        Write-SuccessLine "Found $($repos.Count) matching repositories."
    }
    else {
        Write-SuccessLine "Found $($repos.Count) repositories."
        Write-Host ""
        $typedFilter = Read-Host "Filter by name and press Enter to continue, or just press Enter to show all"
        if ($typedFilter -and $typedFilter.Trim().Length -gt 0) {
            $repos = @($repos | Where-Object { $_.nameWithOwner -like "*$typedFilter*" -or $_.name -like "*$typedFilter*" })
            if ($repos.Count -eq 0) {
                throw "No repositories matched filter '$typedFilter'."
            }
            Write-SuccessLine "Found $($repos.Count) matching repositories."
        }
    }

    Show-RepoTable -Repos $repos
    $selection = Read-RepoSelection -Max $repos.Count
    $repo = $repos[$selection - 1]

    $repoName = [string]$repo.name
    $fullName = [string]$repo.nameWithOwner
    $defaultBranch = '-'
    if ($repo.defaultBranchRef -and $repo.defaultBranchRef.name) {
        $defaultBranch = [string]$repo.defaultBranchRef.name
    }
    $repoUrl = [string]$repo.url
    $cloneUrl = $repoUrl
    if ($cloneUrl -like 'https://github.com/*') {
        $cloneUrl = $cloneUrl + '.git'
    }
    $visibility = '-'
    if ($repo.visibility) {
        $visibility = [string]$repo.visibility
    }
    elseif ($repo.isPrivate) {
        $visibility = 'private'
    }
    else {
        $visibility = 'public'
    }
    $repoKind = if ($repo.isFork) { 'fork' } else { 'source' }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $workspaceRootFull = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    $clonesRoot = Join-Path $workspaceRootFull 'clones'
    $backupsRoot = Join-Path $workspaceRootFull 'backups'
    $cloneFolderName = ($fullName -replace '[^a-zA-Z0-9._-]', '-') + '-' + $timestamp
    $clonePath = Join-Path $clonesRoot $cloneFolderName
    $bundlePath = Join-Path $backupsRoot ($cloneFolderName + '.bundle')
    $metaPath = Join-Path $backupsRoot ($cloneFolderName + '.txt')

    Write-Section "Plan"
    Write-InfoLine 'Repository' $fullName
    Write-InfoLine 'Visibility' $visibility
    Write-InfoLine 'Kind' $repoKind
    Write-InfoLine 'Default branch' $defaultBranch
    Write-InfoLine 'Remote' $cloneUrl
    Write-InfoLine 'Clone path' $clonePath
    Write-InfoLine 'Backup' $bundlePath
    Write-InfoLine 'Commit message' $Message
    Write-InfoLine 'Dry run' ($(if ($DryRun) { 'yes' } else { 'no' }))
    Write-InfoLine 'Push after reset' ($(if ($PushForce) { 'yes (automatic)' } else { 'ask for YES' }))
    Write-InfoLine 'Cleanup clone' ($(if ($RemoveCloneOnSuccess) { 'yes' } else { 'no' }))

    Write-Host ""
    Write-WarnLine "This script clones the selected repository into a dedicated workspace, rewrites its Git history into a single new commit, and can optionally push the rewritten history back to GitHub."
    Write-WarnLine "GitHub issues, pull requests, releases, and other platform data are not deleted by this script."

    if ($DryRun) {
        Write-SuccessLine "Dry run completed. Nothing was changed."
        exit 0
    }

    if (-not $Yes) {
        Write-Host ""
        $confirmation = Read-Host "Type RESET to continue"
        if ($confirmation.ToUpperInvariant() -ne 'RESET') {
            throw "Operation cancelled."
        }
    }

    Write-Section "Preparing workspace"
    New-Item -ItemType Directory -Path $clonesRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $backupsRoot -Force | Out-Null

    if (Test-Path $clonePath) {
        Remove-Item -Path $clonePath -Recurse -Force
    }

    Write-Section "Cloning repository"
    With-GitPromptDisabled {
        $null = Invoke-ToolLive -Path $ghPath -Args @('repo', 'clone', $fullName, $clonePath)
    }
    Write-SuccessLine "Clone completed."

    Set-Location $clonePath

    Write-Section "Creating backup"
    $headBeforeResult = Invoke-ToolCaptured -Path $gitPath -Args @('rev-parse', 'HEAD') -AllowFailure
    $headBefore = ($headBeforeResult.Output -join "`n").Trim()
    $null = Invoke-ToolCaptured -Path $gitPath -Args @('bundle', 'create', $bundlePath, '--all') -NoOutput
    @(
        "repo_name=$repoName"
        "full_name=$fullName"
        "default_branch=$defaultBranch"
        "remote_url=$cloneUrl"
        "old_head=$headBefore"
        "created_at=$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))"
    ) | Set-Content -Path $metaPath -Encoding UTF8
    Write-SuccessLine "Backup created."
    Write-InfoLine 'Bundle' $bundlePath
    Write-InfoLine 'Metadata' $metaPath

    Write-Section "Rewriting history"
    $currentBranchResult = Invoke-ToolCaptured -Path $gitPath -Args @('branch', '--show-current')
    $currentBranch = ($currentBranchResult.Output -join "`n").Trim()
    if (-not $currentBranch -or $currentBranch -eq '-') {
        $currentBranch = $defaultBranch
    }
    if (-not $currentBranch -or $currentBranch -eq '-') {
        throw "Could not determine the current branch."
    }

    Write-InfoLine 'Current branch' $currentBranch
    $tempBranch = 'ghr-reset-' + $timestamp

    $userNameResult = Invoke-ToolCaptured -Path $gitPath -Args @('config', '--get', 'user.name') -AllowFailure
    $userName = Get-TrimmedOutput -Result $userNameResult
    $userEmailResult = Invoke-ToolCaptured -Path $gitPath -Args @('config', '--get', 'user.email') -AllowFailure
    $userEmail = Get-TrimmedOutput -Result $userEmailResult
    $commitGpgSignResult = Invoke-ToolCaptured -Path $gitPath -Args @('config', '--get', 'commit.gpgsign') -AllowFailure
    $commitGpgSign = Get-TrimmedOutput -Result $commitGpgSignResult
    $gpgFormatResult = Invoke-ToolCaptured -Path $gitPath -Args @('config', '--get', 'gpg.format') -AllowFailure
    $gpgFormat = Get-TrimmedOutput -Result $gpgFormatResult
    $signingKeyResult = Invoke-ToolCaptured -Path $gitPath -Args @('config', '--get', 'user.signingkey') -AllowFailure
    $signingKey = Get-TrimmedOutput -Result $signingKeyResult

    if (-not $userName) {
        Write-WarnLine "git user.name is not set in your Git config."
    }
    else {
        Write-InfoLine 'Commit name' $userName
    }

    if (-not $userEmail) {
        Write-WarnLine "git user.email is not set in your Git config."
    }
    else {
        Write-InfoLine 'Commit email' $userEmail
    }

    $signMode = 'inherit'
    if ($Sign) {
        $signMode = 'force-sign'
    }
    elseif ($NoSign) {
        $signMode = 'force-no-sign'
    }
    Write-InfoLine 'Signing mode' $signMode
    Write-InfoLine 'commit.gpgsign' $(if ($commitGpgSign) { $commitGpgSign } else { '(not set)' })
    Write-InfoLine 'gpg.format' $(if ($gpgFormat) { $gpgFormat } else { '(not set)' })
    Write-InfoLine 'Signing key' $(if ($signingKey) { $signingKey } else { '(not set)' })

    if (-not $userName -or -not $userEmail) {
        throw "git user.name and user.email must be configured before creating the replacement commit."
    }

    Write-StepLine "Creating orphan branch"
    $null = Invoke-ToolLive -Path $gitPath -Args @('checkout', '--orphan', $tempBranch)

    Write-StepLine "Staging files"
    $null = Invoke-ToolLive -Path $gitPath -Args @('add', '--all')

    Write-StepLine "Checking staged changes"
    & $gitPath diff --cached --quiet
    $diffExit = $LASTEXITCODE
    if ($diffExit -ne 0 -and $diffExit -ne 1) {
        throw "git diff --cached --quiet failed with exit code $diffExit."
    }

    Write-StepLine "Creating commit"
    $commitArgs = @('commit')
    if ($Sign) {
        $commitArgs += '-S'
    }
    elseif ($NoSign) {
        $commitArgs += '--no-gpg-sign'
    }
    if ($diffExit -eq 0) {
        $commitArgs += '--allow-empty'
    }
    $commitArgs += @('-m', $Message)
    Try-CreateCommit -GitPath $gitPath -CommitArgs $commitArgs

    Write-StepLine "Replacing original branch"
    $null = Invoke-ToolLive -Path $gitPath -Args @('branch', '-M', $currentBranch)

    $newHeadResult = Invoke-ToolCaptured -Path $gitPath -Args @('rev-parse', '--short', 'HEAD')
    $newHead = ($newHeadResult.Output -join "`n").Trim()
    $newCountResult = Invoke-ToolCaptured -Path $gitPath -Args @('rev-list', '--count', 'HEAD')
    $newCommitCount = [int](($newCountResult.Output -join "`n").Trim())

    Write-SuccessLine "History rewrite completed."
    Write-InfoLine 'Branch' $currentBranch
    Write-InfoLine 'New HEAD' $newHead
    Write-InfoLine 'Commits now' "$newCommitCount"

    $fullHeadResult = Invoke-ToolCaptured -Path $gitPath -Args @('rev-parse', 'HEAD')
    $fullHead = ($fullHeadResult.Output -join "`n").Trim()
    $repoWebUrl = $repoUrl
    $commitWebUrl = $null

    $shouldPush = $false
    if ($PushForce) {
        $shouldPush = $true
    }
    else {
        Write-Section "Push confirmation"
        Write-WarnLine "This will push the rewritten history to GitHub using --force-with-lease."
        $pushConfirmation = Read-Host "Type YES to push now"
        $pushValue = $pushConfirmation.ToUpperInvariant()
        if ($pushValue -eq 'YES' -or $pushValue -eq 'Y') {
            $shouldPush = $true
        }
        else {
            Write-WarnLine "Push skipped."
        }
    }

    if ($shouldPush) {
        Write-Section "Pushing rewritten history"
        With-GitPromptDisabled {
            $null = Invoke-ToolLive -Path $gitPath -Args @('push', 'origin', $currentBranch, '--force-with-lease')
        }
        Write-SuccessLine "Push completed."
        if ($repoWebUrl -like 'https://github.com/*' -and $fullHead) {
            $commitWebUrl = $repoWebUrl.TrimEnd('/') + '/commit/' + $fullHead
        }
    }

    if ($RemoveCloneOnSuccess -and $shouldPush) {
        Set-Location $originalLocation
        if (Test-Path $clonePath) {
            Remove-Item -Path $clonePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-SuccessLine "Workspace clone removed."
        }
    }

    Write-Section "Repository links"
    if ($repoWebUrl) {
        Write-InfoLine 'Repository URL' $repoWebUrl
    }
    if ($commitWebUrl) {
        Write-InfoLine 'Commit URL' $commitWebUrl
    }
    else {
        Write-InfoLine 'Commit URL' '(available after push)'
    }
    if (-not ($RemoveCloneOnSuccess -and $shouldPush)) {
        Write-InfoLine 'Workspace clone' $clonePath
    }
}
catch {
    Write-Host ""
    Write-ErrorLine $_.Exception.Message
    exit 1
}
finally {
    try {
        Set-Location $originalLocation
    }
    catch {
    }
}
