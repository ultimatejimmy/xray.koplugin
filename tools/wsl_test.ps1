param (
    [switch]$Watch
)

# Ensure WSL passes software rendering and X11 driver flags to fix graphics crashes & black screen issues in Copy Mode
$env:LIBGL_ALWAYS_SOFTWARE = "1"
$env:SDL_VIDEO_DRIVER = "x11"
$env:SDL_VIDEODRIVER = "x11"

$EnvList = @("LIBGL_ALWAYS_SOFTWARE/u", "SDL_VIDEO_DRIVER/u", "SDL_VIDEODRIVER/u")
foreach ($item in $EnvList) {
    $varName = $item.Split('/')[0]
    if ($env:WSLENV) {
        if ($env:WSLENV -notlike "*$varName*") {
            $env:WSLENV = "$env:WSLENV:$item"
        }
    } else {
        $env:WSLENV = $item
    }
}

$PluginDir = "xray.koplugin"
$WSLDest = "~/.config/koreader/plugins/xray.koplugin"
$SyntaxScript = "tools/check_syntax.py"

# Probe for the squashfs-root location in WSL
$SquashPath = ""
$UserNameLower = $env:USERNAME.ToLower()
$ProbedPaths = @(
    "/home/jimmy/squashfs-root",
    "/home/$env:USERNAME/squashfs-root",
    "/home/$UserNameLower/squashfs-root",
    "/mnt/c/Users/$env:USERNAME/squashfs-root",
    "/mnt/c/Users/$UserNameLower/squashfs-root"
)
foreach ($path in $ProbedPaths) {
    $null = wsl test -d $path
    if ($LASTEXITCODE -eq 0) {
        $SquashPath = $path
        break
    }
}
if (-not $SquashPath) {
    $SquashPath = "/home/jimmy/squashfs-root"
}
Write-Host "Using KOReader installation path: $SquashPath" -ForegroundColor Yellow

function Run-Workflow {
    Write-Host "`n--- Starting Verification Workflow ---" -ForegroundColor Cyan
    
    # 1. Syntax Check
    Write-Host "Checking Lua syntax..." -NoNewline
    $syntaxResult = python $SyntaxScript $PluginDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host $syntaxResult
        return $false
    }
    Write-Host " PASSED" -ForegroundColor Green

    # 1.5 Translation Sync Check
    Write-Host "Checking translation sync..." -NoNewline
    $transResult = python tools/check_translations.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host $transResult
        return $false
    }
    Write-Host " PASSED" -ForegroundColor Green

    # 2. Unit Tests
    Write-Host "Running unit tests (Bundled LuaJIT in WSL)..."
    wsl env SQUASHFS_ROOT=$SquashPath "$SquashPath/usr/lib/koreader/luajit" tools/spec_runner.lua
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tests FAILED. Aborting sync." -ForegroundColor Red
        return $false
    }
    Write-Host "Tests PASSED" -ForegroundColor Green

    # 3. Sync
    Write-Host "Syncing to WSL..." -NoNewline
    wsl mkdir -p (Split-Path $WSLDest -Parent)
    
    # Smart Config Merge (mimics xray_updater.lua)
    # 1. Backup existing keys if file exists
    $ConfigSubPath = "xray_config.lua"
    $BackupPath = "/tmp/xray_config_backup.lua"
    wsl sh -c "if [ -f $WSLDest/$ConfigSubPath ]; then cp $WSLDest/$ConfigSubPath $BackupPath; fi"

    # 2. Sync (this will overwrite xray_config.lua with the one from Windows)
    # We exclude xray.log and .sdr folders to avoid deleting runtime data
    wsl rsync -rv --delete --exclude="xray.log" --exclude="*.sdr/" "./$PluginDir/" "$WSLDest/"
    
    # 3. Restore keys from backup
    $MergeScript = "tools/merge_config.py"
    $winPath = (Get-Item ".").FullName -replace '\\', '/'
    $WslCwd = (wsl wslpath -u $winPath).Trim()
    wsl python3 "$WslCwd/$MergeScript" "$WSLDest/$ConfigSubPath" "$BackupPath"
    wsl rm -f "$BackupPath"

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        return $false
    }
    Write-Host " SUCCESS" -ForegroundColor Green

    # 4. Restart KOReader
    Write-Host "Restarting KOReader..." -ForegroundColor Cyan
    wsl pkill -9 -f koreader 2>$null
    wsl pkill -9 -f AppRun 2>$null
    Start-Sleep -Seconds 1

    # Define start command
    $DefaultCmd = "C:\Windows\System32\wsl.exe --exec dbus-launch --exit-with-session bash -c `"cd $SquashPath && ./AppRun`""
    $StartCmd = if ($env:KOREADER_START_CMD) { $env:KOREADER_START_CMD } else { $DefaultCmd }
    
    Write-Host "Starting KOReader: $StartCmd"
    # Use cmd /c start to ensure it's fully detached and quotes are preserved
    $cmdLine = "/c start `"`" $StartCmd"
    Start-Process cmd.exe -ArgumentList $cmdLine -WindowStyle Hidden

    Write-Host "`nReady!" -ForegroundColor Green
    return $true
}

if ($Watch) {
    Write-Host "Watching for changes in $PluginDir..." -ForegroundColor Magenta
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = (Get-Item "./$PluginDir").FullName
    $watcher.Filter = "*.lua"
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true

    $action = {
        Run-Workflow
    }

    Register-ObjectEvent $watcher "Changed" -Action $action
    Register-ObjectEvent $watcher "Created" -Action $action
    Register-ObjectEvent $watcher "Deleted" -Action $action
    Register-ObjectEvent $watcher "Renamed" -Action $action

    while ($true) { Start-Sleep -Seconds 1 }
} else {
    Run-Workflow
}
