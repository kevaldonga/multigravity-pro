<#
.SYNOPSIS
Run multiple Antigravity CLI (agy) accounts and profiles simultaneously.
#>

param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$cmd,
    
    [Parameter(Position = 1, Mandatory = $false)]
    [string]$arg1,

    [Parameter(Position = 2, Mandatory = $false)]
    [string]$arg2,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArgs
)

$BASE = if ($env:MULTIGRAVITY_CLI_HOME) { $env:MULTIGRAVITY_CLI_HOME } else { "$env:USERPROFILE\AntigravityCliProfiles" }
$REAL_USERPROFILE = $env:USERPROFILE

function Find-Agy {
    if ($env:MULTIGRAVITY_CLI_APP) {
        if (Test-Path $env:MULTIGRAVITY_CLI_APP) { return $env:MULTIGRAVITY_CLI_APP }
    }

    $paths = @(
        "$env:LOCALAPPDATA\Programs\Antigravity\bin\agy.exe",
        "$env:LOCALAPPDATA\Programs\Antigravity\agy.exe",
        "$env:PROGRAMFILES\Antigravity\bin\agy.exe",
        "$env:PROGRAMFILES\Antigravity\agy.exe",
        "$env:USERPROFILE\.gemini\antigravity-cli\bin\agy.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }

    # Try to find in PATH
    $exeCommand = Get-Command agy.exe -ErrorAction SilentlyContinue
    if ($exeCommand) { return $exeCommand.Source }
    $exeCommand2 = Get-Command agy -ErrorAction SilentlyContinue
    if ($exeCommand2) { return $exeCommand2.Source }

    return $null
}

$APP = Find-Agy

function Get-TemplatesDir {
    return "$BASE\.templates"
}

function Test-AuthOnly {
    param($PROFILE)
    return Test-Path "$BASE\$PROFILE\.auth-only"
}

function Write-Usage {
    Write-Host "Usage: multigravity-cli <command> [args...]"
    Write-Host ""
    Write-Host "Run multiple Antigravity CLI (agy) sessions with different accounts simultaneously."
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  <name> [args...]                 Launch Antigravity CLI with the given profile"
    Write-Host "  new <name> [options]            Create a new CLI profile"
    Write-Host "      --auth-only                 Share CLI settings & MCP, isolate only accounts"
    Write-Host "      --from <template>           Create from a saved template"
    Write-Host "      --copy-from <src>           Clone auth credentials from an existing profile"
    Write-Host "  list                            List all profiles and active accounts"
    Write-Host "  whoami [name]                   Display active account email for profile(s)"
    Write-Host "  status                          Dashboard: running/stopped, account, type, last used, size"
    Write-Host "  clone <src> <dest>              Duplicate a profile and its auth state"
    Write-Host "  rename <old> <new>              Rename a profile"
    Write-Host "  delete <name>                   Delete a profile and its isolated state"
    Write-Host "  template save <profile> <name>  Save profile as reusable template"
    Write-Host "  template list                   List available templates"
    Write-Host "  template delete <name>          Delete a template"
    Write-Host "  export <name> [path]            Export profile to .zip archive"
    Write-Host "  import <archive> [name]         Import profile from .zip archive"
    Write-Host "  doctor                          Check environment and CLI health"
    Write-Host "  stats                           Show storage usage per profile"
    Write-Host "  completion                      Show shell completion setup instructions"
    Write-Host "  help                            Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  multigravity-cli new work"
    Write-Host "  multigravity-cli work"
    Write-Host "  multigravity-cli work -p 'Explain this repo'"
}

function Validate-Name {
    param($name)
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Error "Error: profile name required"
        exit 1
    }
    if ($name -notmatch "^[a-zA-Z0-9][a-zA-Z0-9-]*$") {
        Write-Error "Error: profile name must start with alphanumeric and contain only letters, numbers, or hyphens"
        exit 1
    }
}

function Bridge-Dotfiles {
    param($ProfileDir)

    foreach ($f in @(".gitconfig", ".ssh")) {
        $src = Join-Path $REAL_USERPROFILE $f
        $dest = Join-Path $ProfileDir $f
        if ((Test-Path $src) -and !(Test-Path $dest)) {
            try {
                New-Item -ItemType SymbolicLink -Path $dest -Target $src -Force -ErrorAction SilentlyContinue | Out-Null
            } catch {
                Copy-Item -Path $src -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Get-ProfileEmail {
    param($PROFILE)
    $accFile = "$BASE\$PROFILE\.gemini\google_accounts.json"
    if (Test-Path $accFile) {
        try {
            $json = Get-Content $accFile -Raw | ConvertFrom-Json
            if ($json.active) { return $json.active }
        } catch {}
    }
    return "(not signed in)"
}

function Invoke-CreateProfileLayout {
    param($PROFILE)
    $pDir = "$BASE\$PROFILE"

    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\config\projects" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\conversations" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\brain" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\cache" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\log" | Out-Null

    Bridge-Dotfiles $pDir

    $pbtxt = "$pDir\.gemini\antigravity-cli\jetski_state.pbtxt"
    if (!(Test-Path $pbtxt)) {
        @'
post_onboarding:  {
  completed_steps:  POST_ONBOARDING_STEP_TYPE_MANAGER_WELCOME
  completed_steps:  POST_ONBOARDING_STEP_TYPE_USAGE_MODE
  completed_steps:  POST_ONBOARDING_STEP_TYPE_AGENT_CONFIGURATION
  completed_steps:  POST_ONBOARDING_STEP_TYPE_ADD_WORKSPACE
}
'@ | Set-Content -Path $pbtxt -Encoding UTF8
    }

    $defaultSettings = "$REAL_USERPROFILE\.gemini\antigravity-cli\settings.json"
    $targetSettings = "$pDir\.gemini\antigravity-cli\settings.json"
    if ((Test-Path $defaultSettings) -and !(Test-Path $targetSettings)) {
        Copy-Item -Path $defaultSettings -Destination $targetSettings -Force
    }
}

function Invoke-CreateAuthOnlyLayout {
    param($PROFILE)
    $pDir = "$BASE\$PROFILE"

    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\config" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\conversations" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\brain" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\cache" | Out-Null
    New-Item -ItemType Directory -Force -Path "$pDir\.gemini\antigravity-cli\log" | Out-Null

    New-Item -ItemType File -Force -Path "$pDir\.auth-only" | Out-Null

    Bridge-Dotfiles $pDir

    $defaultSettings = "$REAL_USERPROFILE\.gemini\antigravity-cli\settings.json"
    $targetSettings = "$pDir\.gemini\antigravity-cli\settings.json"
    if ((Test-Path $defaultSettings) -and !(Test-Path $targetSettings)) {
        try {
            New-Item -ItemType SymbolicLink -Path $targetSettings -Target $defaultSettings -Force -ErrorAction SilentlyContinue | Out-Null
        } catch {
            Copy-Item -Path $defaultSettings -Destination $targetSettings -Force
        }
    }

    $defaultMcp = "$REAL_USERPROFILE\.gemini\config\mcp_config.json"
    $targetMcp = "$pDir\.gemini\config\mcp_config.json"
    if ((Test-Path $defaultMcp) -and !(Test-Path $targetMcp)) {
        try {
            New-Item -ItemType SymbolicLink -Path $targetMcp -Target $defaultMcp -Force -ErrorAction SilentlyContinue | Out-Null
        } catch {
            Copy-Item -Path $defaultMcp -Destination $targetMcp -Force
        }
    }
}

function Invoke-NewProfile {
    param($allArgs)

    $profile = $null
    $authOnly = $false
    $fromTemplate = $null
    $copyFrom = $null

    for ($i = 0; $i -lt $allArgs.Length; $i++) {
        $a = $allArgs[$i]
        if ($a -eq "--auth-only") { $authOnly = $true }
        elseif ($a -eq "--from") { $i++; $fromTemplate = $allArgs[$i] }
        elseif ($a -eq "--copy-from") { $i++; $copyFrom = $allArgs[$i] }
        elseif (!$profile) { $profile = $a }
    }

    Validate-Name $profile
    $pDir = "$BASE\$profile"

    if (Test-Path $pDir) {
        Write-Error "Error: profile '$profile' already exists"
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $BASE | Out-Null

    if ($fromTemplate) {
        $tplPath = "$BASE\.templates\$fromTemplate"
        if (!(Test-Path $tplPath)) {
            Write-Error "Error: template '$fromTemplate' does not exist. Run: multigravity-cli template list"
            exit 1
        }
        Write-Host "Creating profile '$profile' from template '$fromTemplate'..."
        Copy-Item -Path $tplPath -Destination $pDir -Recurse
    } elseif ($copyFrom) {
        $srcDir = "$BASE\$copyFrom"
        if (!(Test-Path $srcDir)) {
            Write-Error "Error: source profile '$copyFrom' does not exist"
            exit 1
        }
        Write-Host "Creating profile '$profile' copying auth from '$copyFrom'..."
        Invoke-CreateProfileLayout $profile
        foreach ($f in @("google_accounts.json", "oauth_creds.json", "settings.json")) {
            $sf = "$srcDir\.gemini\$f"
            if (Test-Path $sf) {
                Copy-Item -Path $sf -Destination "$pDir\.gemini\$f" -Force
            }
        }
    } elseif ($authOnly) {
        Invoke-CreateAuthOnlyLayout $profile
    } else {
        Invoke-CreateProfileLayout $profile
    }

    Write-Host "Created profile '$profile' at $pDir"
    Write-Host "To use this profile, run: multigravity-cli $profile"
}

function Invoke-LaunchProfile {
    param($PROFILE, $ArgsToForward)

    Validate-Name $PROFILE
    $pDir = "$BASE\$PROFILE"

    if (!(Test-Path $pDir)) {
        Write-Error "Error: profile '$PROFILE' does not exist. Run: multigravity-cli new $PROFILE"
        exit 1
    }

    if ([string]::IsNullOrEmpty($APP) -or !(Test-Path $APP)) {
        Write-Error "Error: Antigravity CLI ('agy.exe') not found. Ensure it is in PATH or set MULTIGRAVITY_CLI_APP."
        exit 1
    }

    if (Test-AuthOnly $PROFILE) {
        Invoke-CreateAuthOnlyLayout $PROFILE
    } else {
        Invoke-CreateProfileLayout $PROFILE
    }

    $email = Get-ProfileEmail $PROFILE
    if ($email -ne "(not signed in)") {
        Write-Host "Using profile '$PROFILE' ($email)" -ForegroundColor Cyan
    } else {
        Write-Host "Using profile '$PROFILE' [Sign in required]" -ForegroundColor Yellow
    }

    $env:USERPROFILE = $pDir
    $env:MULTIGRAVITY_CLI_PROFILE = $PROFILE

    if ($ArgsToForward) {
        & $APP @ArgsToForward
    } else {
        & $APP
    }
}

function Invoke-ListProfiles {
    Write-Host "Existing Antigravity CLI profiles:"
    if (Test-Path $BASE) {
        $profiles = Get-ChildItem -Directory -Path $BASE | Where-Object { $_.Name -ne ".templates" }
        if ($profiles.Count -gt 0) {
            foreach ($p in $profiles) {
                $email = Get-ProfileEmail $p.Name
                $tag = if (Test-AuthOnly $p.Name) { " [auth-only]" } else { "" }
                Write-Host ("  * {0,-16} {1,-30}{2}" -f $p.Name, $email, $tag)
            }
        } else {
            Write-Host "(none)"
        }
    } else {
        Write-Host "(none)"
    }
}

function Invoke-Whoami {
    param($target)

    if ($target) {
        $pDir = "$BASE\$target"
        if (!(Test-Path $pDir)) {
            Write-Error "Error: profile '$target' does not exist"
            exit 1
        }
        $email = Get-ProfileEmail $target
        $type = if (Test-AuthOnly $target) { "auth-only" } else { "full" }
        Write-Host "Profile: $target"
        Write-Host "Account: $email"
        Write-Host "Type:    $type"
        Write-Host "Path:    $pDir"
        return
    }

    if ($env:MULTIGRAVITY_CLI_PROFILE) {
        Write-Host "Active Environment Profile: $env:MULTIGRAVITY_CLI_PROFILE ($(Get-ProfileEmail $env:MULTIGRAVITY_CLI_PROFILE))"
        Write-Host ""
    }

    Write-Host "Profile Accounts:"
    Write-Host (" {0,-16} {1,-32} {2,-10}" -f "PROFILE", "ACCOUNT", "TYPE")
    Write-Host (" {0,-16} {1,-32} {2,-10}" -f "-------", "-------", "----")

    if (Test-Path $BASE) {
        $profiles = Get-ChildItem -Directory -Path $BASE | Where-Object { $_.Name -ne ".templates" }
        foreach ($p in $profiles) {
            $email = Get-ProfileEmail $p.Name
            $type = if (Test-AuthOnly $p.Name) { "auth-only" } else { "full" }
            Write-Host (" {0,-16} {1,-32} {2,-10}" -f $p.Name, $email, $type)
        }
    }
}

function Get-FolderSize {
    param($Path)
    $files = Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue
    $size = 0
    if ($files) {
        $size = ($files | Measure-Object -Property Length -Sum).Sum
    }
    if ($size -ge 1GB) { "{0:N2} GB" -f ($size / 1GB) }
    elseif ($size -ge 1MB) { "{0:N2} MB" -f ($size / 1MB) }
    elseif ($size -ge 1KB) { "{0:N2} KB" -f ($size / 1KB) }
    else { "$size B" }
}

function Invoke-Status {
    if (!(Test-Path $BASE)) {
        Write-Host "No profiles found."
        return
    }

    Write-Host (" {0,-14} {1,-26} {2,-10} {3,-11} {4,-8}" -f "PROFILE", "ACCOUNT", "STATUS", "TYPE", "SIZE")
    Write-Host (" {0,-14} {1,-26} {2,-10} {3,-11} {4,-8}" -f "-------", "-------", "------", "----", "----")

    $profiles = Get-ChildItem -Directory -Path $BASE | Where-Object { $_.Name -ne ".templates" }
    foreach ($p in $profiles) {
        $email = Get-ProfileEmail $p.Name
        if ($email.Length -gt 25) { $email = $email.Substring(0, 22) + "..." }
        $type = if (Test-AuthOnly $p.Name) { "auth-only" } else { "full" }
        $size = Get-FolderSize $p.FullName
        Write-Host (" {0,-14} {1,-26} {2,-10} {3,-11} {4,-8}" -f $p.Name, $email, "stopped", $type, $size)
    }
}

function Invoke-DoctorCli {
    $errors = 0
    $warnings = 0

    Write-Host "Checking multigravity-cli environment..."

    if ($APP -and (Test-Path $APP)) {
        Write-Host "  [OK] Antigravity CLI: Found at $APP"
    } else {
        Write-Host "  [FAIL] Antigravity CLI: 'agy.exe' not found in PATH or standard paths."
        $errors++
    }

    $cmdObj = Get-Command multigravity-cli -ErrorAction SilentlyContinue
    if ($cmdObj) {
        Write-Host "  [OK] Global Command: $($cmdObj.Source)"
    } else {
        Write-Host "  [WARN] Global Command: 'multigravity-cli' not found in PATH."
        $warnings++
    }

    if (Test-Path $BASE) {
        Write-Host "  [OK] Profile Storage: $BASE (exists)"
    } else {
        Write-Host "  [OK] Profile Storage: $BASE (will be created on first profile)"
    }

    $hostAcc = "$REAL_USERPROFILE\.gemini\google_accounts.json"
    if (Test-Path $hostAcc) {
        try {
            $json = Get-Content $hostAcc -Raw | ConvertFrom-Json
            if ($json.active) {
                Write-Host "  [OK] Default Host Account: $($json.active)"
            }
        } catch {}
    }

    Write-Host ""
    if ($errors -eq 0) {
        Write-Host "Everything looks good! Ready to use multigravity-cli."
    } else {
        Write-Host "Found $errors error(s). Please fix them before using multigravity-cli."
    }
}

function Invoke-CloneProfile {
    param($SRC, $DEST)
    Validate-Name $SRC
    Validate-Name $DEST

    $SRC_DIR = "$BASE\$SRC"
    $DEST_DIR = "$BASE\$DEST"

    if (!(Test-Path $SRC_DIR)) {
        Write-Error "Error: source profile '$SRC' does not exist"
        exit 1
    }
    if (Test-Path $DEST_DIR) {
        Write-Error "Error: destination profile '$DEST' already exists"
        exit 1
    }

    Write-Host "Cloning profile '$SRC' to '$DEST'..."
    Copy-Item -Path $SRC_DIR -Destination $DEST_DIR -Recurse
    Write-Host "Successfully cloned '$SRC' to '$DEST'"
}

function Invoke-RenameProfile {
    param($OLD, $NEW)
    Validate-Name $OLD
    Validate-Name $NEW

    $OLD_DIR = "$BASE\$OLD"
    $NEW_DIR = "$BASE\$NEW"

    if (!(Test-Path $OLD_DIR)) {
        Write-Error "Error: profile '$OLD' does not exist"
        exit 1
    }
    if (Test-Path $NEW_DIR) {
        Write-Error "Error: profile '$NEW' already exists"
        exit 1
    }

    Rename-Item -Path $OLD_DIR -NewName $NEW
    Write-Host "Renamed profile '$OLD' to '$NEW'"
}

function Invoke-DeleteProfile {
    param($PROFILE)
    Validate-Name $PROFILE

    $PROFILE_DIR = "$BASE\$PROFILE"
    if (!(Test-Path $PROFILE_DIR)) {
        Write-Error "Error: profile '$PROFILE' does not exist"
        exit 1
    }

    $confirm = Read-Host "Delete profile '$PROFILE' and all its data? [y/N]"
    if ($confirm -match "^[yY](es)?$") {
        Remove-Item -Path $PROFILE_DIR -Recurse -Force
        Write-Host "Deleted profile '$PROFILE'"
    } else {
        Write-Host "Cancelled"
    }
}

# Dispatch
switch ($cmd) {
    "new" {
        $allArgs = @()
        if ($arg1) { $allArgs += $arg1 }
        if ($arg2) { $allArgs += $arg2 }
        if ($ForwardArgs) { $allArgs += $ForwardArgs }
        Invoke-NewProfile $allArgs
    }
    "list" {
        Invoke-ListProfiles
    }
    "whoami" {
        Invoke-Whoami $arg1
    }
    "status" {
        Invoke-Status
    }
    "clone" {
        Invoke-CloneProfile $arg1 $arg2
    }
    "rename" {
        Invoke-RenameProfile $arg1 $arg2
    }
    "delete" {
        Invoke-DeleteProfile $arg1
    }
    "doctor" {
        Invoke-DoctorCli
    }
    "help" {
        Write-Usage
    }
    "--help" {
        Write-Usage
    }
    "-h" {
        Write-Usage
    }
    "" {
        Write-Usage
        exit 1
    }
    default {
        $AllArgs = @()
        if ($arg1) { $AllArgs += $arg1 }
        if ($arg2) { $AllArgs += $arg2 }
        if ($ForwardArgs) { $AllArgs += $ForwardArgs }
        Invoke-LaunchProfile $cmd $AllArgs
    }
}
