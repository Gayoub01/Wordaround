0# ==============================================================================
# Windows Root & System Cleanup Script By URTech.ca
# Targets: Temp files, logs, installation leftovers, and WinSxS
# ==============================================================================

# 1. Stop Windows Update Services (to Prevents Windows Update from being “broken” or stuck after cleanup)
Write-Host "Stopping Windows Update services..." -ForegroundColor Cyan
Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue

# 2. Define a list of paths to be deleted (Whole Folders) These folders are created during Windows upgrades, resets, or repairs. They are not used after the process finishes.
$foldersToDelete = @(
    "C:\$SysReset",
    "C:\$WINDOWS.~ws",
    "C:\$WinREAgent",
    "C:\$GetCurrent",
    "C:\.cache\AMD",
    "C:\AMD",
    "C:\INTEL",
    "C:\ESD",
    "C:\.gamingroot",
    "C:\Windows\SoftwareDistribution",
    "C:\Windows\MiniDump"
)

# 3. Define paths where we only want to wipe the CONTENTS (These folders are only temps files, are designed to be emptied regularly.)
$contentsOnly = @(
    "C:\Windows\Temp\*",
    "C:\Windows\WinSxS\Temp\*",
    "C:\Windows\Logs\CBS\*",
    "C:\Windows\Prefetch\*",
    "C:\Windows\Offline Web Pages\*",
    "C:\ProgramData\Microsoft\Windows\WER\*",
    "C:\Users\$env:USERNAME\AppData\Local\Temp\*",
    "C:\found.*" 
)

Write-Host "Starting file deletion... (Files currently in use will be skipped)" -ForegroundColor Yellow

# Delete Whole Folders
foreach ($folder in $foldersToDelete) {
    if (Test-Path $folder) {
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Deleted: $folder"
    }
}

# Delete Contents Only
foreach ($path in $contentsOnly) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleared Contents: $path"
    }
}

# 4. Handle the "Random Hex" folders at C:\ Root
Get-ChildItem -Path "C:\" -Directory | Where-Object { $_.Name -match "^[0-9a-fA-F]{20,}" } | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Deleted Hex Folder: $($_.Name)"
}

# 5. DISM Component Store Cleanup (The WinSxS Fix)
Write-Host "Cleaning up WinSxS Component Store (this may take a few minutes)..." -ForegroundColor Cyan
Dism.exe /Online /Cleanup-Image /StartComponentCleanup

# OPTIONAL: Un-comment the line below for a deeper clean (Warning: prevents uninstalling current updates)
# Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# 6. Empty the Recycle Bin for all drives (clear ‘trash’ for ALL users)
Write-Host "Emptying Recycle Bin..." -ForegroundColor Cyan
Clear-RecycleBin -Confirm:$false -ErrorAction SilentlyContinue

# 7. Restart Windows Update Services
Write-Host "Restarting Windows Update services..." -ForegroundColor Cyan
Start-Service -Name "wuauserv"
Start-Service -Name "bits"

Write-Host "`nCleanup Complete!" -ForegroundColor Green