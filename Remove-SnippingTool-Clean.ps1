<#
.SYNOPSIS
  Uninstall Microsoft Snipping Tool (Microsoft.ScreenSketch) and clean leftovers:
  - AppX uninstall (current user; optional all users)
  - Optional provisioned removal (preinstall for NEW users)
  - Remove leftover package folders (current user; optional all profiles)
  - Remove Snipping Tool-only registry keys (with .reg backup)
  - Remove Start Menu shortcuts for Snipping Tool only (current user + all users)
  - Refresh Start Menu/Explorer processes (no reboot required)
  - test test

.PARAMETER AllUsers
  Attempt removal for all user profiles found (requires Admin).

.PARAMETER RemoveProvisioned
  Remove provisioned package from the OS image so it won’t install for NEW user profiles.

.PARAMETER PurgeAllProfiles
  Delete leftover Snipping Tool folders for ALL local user profiles under C:\Users\* (requires Admin).

.PARAMETER PurgeRegistry
  Remove Snipping Tool-only registry keys (exports backups first).

.PARAMETER DeepRegistryClean
  More aggressive registry cleanup for ScreenSketch package activation keys in HKCU (still Snipping Tool only).

.PARAMETER RemoveStartMenuShortcuts
  Removes Snipping Tool-related .lnk shortcuts from Start Menu program folders (current user + ProgramData). 

.PARAMETER RefreshShell
  Restarts StartMenuExperienceHost and Explorer to refresh Start immediately

.PARAMETER BackupDir
  Folder where .reg backups will be exported.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [switch]$AllUsers,
  [switch]$RemoveProvisioned,
  [switch]$PurgeAllProfiles,
  [switch]$PurgeRegistry,
  [switch]$DeepRegistryClean,
  [switch]$RemoveStartMenuShortcuts,
  [switch]$RefreshShell,
  [string]$BackupDir = "$env:PUBLIC\SnippingTool_RegistryBackup"
)

$PkgName     = "Microsoft.ScreenSketch"
$PublisherId = "8wekyb3d8bbwe"

function Write-Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err ($m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

function Ensure-Dir($path){
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

function Stop-SnippingToolProcs {
  Write-Info "Stopping Snipping Tool processes (if running)..."
  Get-Process -Name "SnippingTool","ScreenSketch" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($PSCmdlet.ShouldProcess("$($_.Name) PID=$($_.Id)", "Stop-Process -Force")) {
      try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; Write-Info "Stopped $($_.Name) PID=$($_.Id)" }
      catch { Write-Warn "Could not stop $($_.Name): $($_.Exception.Message)" }
    }
  }
}

function Remove-AppxForCurrentUser {
  Write-Info "Removing Snipping Tool for CURRENT user..."
  $pkgs = Get-AppxPackage -Name "*$PkgName*" -ErrorAction SilentlyContinue
  if (-not $pkgs) { Write-Warn "No Snipping Tool package found for current user."; return }

  foreach ($p in $pkgs) {
    Write-Info "Found: $($p.PackageFullName)"
    if ($PSCmdlet.ShouldProcess($p.PackageFullName, "Remove-AppxPackage")) {
      try {
        Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
        Write-Info "Removed (current user): $($p.PackageFullName)"
      } catch {
        Write-Err "Failed removing current user package: $($_.Exception.Message)"
      }
    }
  }
}

function Remove-AppxForAllUsers {
  Write-Info "Removing Snipping Tool for ALL users (best effort)..."
  $allPkgs = Get-AppxPackage -AllUsers -Name "*$PkgName*" -ErrorAction SilentlyContinue
  if (-not $allPkgs) { Write-Warn "No Snipping Tool package found for all users."; return }

  foreach ($pkg in $allPkgs) {
    $pfn = $pkg.PackageFullName
    Write-Info "Package: $pfn"

    foreach ($u in $pkg.PackageUserInformation) {
      if ($u.InstallState -eq "Installed") {
        $sid = $u.UserSecurityId.Value
        if ($PSCmdlet.ShouldProcess("SID=$sid Package=$pfn", "Remove-AppxPackage -User")) {
          try {
            Remove-AppxPackage -Package $pfn -User $sid -ErrorAction Stop
            Write-Info "Removed for user SID $sid"
          } catch {
            Write-Warn "Could not remove for SID ${sid}: $($_.Exception.Message)"
          }
        }
      }
    }
  }
}

function Remove-Provisioned {
  Write-Info "Removing provisioned Snipping Tool package (preinstall for new users)..."
  try {
    $prov = Get-AppxProvisionedPackage -Online |
      Where-Object { $_.DisplayName -like "*ScreenSketch*" -or $_.PackageName -like "*ScreenSketch*" }

    if (-not $prov) { Write-Warn "No provisioned ScreenSketch package found."; return }

    foreach ($p in $prov) {
      Write-Info "Provisioned: $($p.PackageName)"
      if ($PSCmdlet.ShouldProcess($p.PackageName, "Remove-AppxProvisionedPackage -Online")) {
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
        Write-Info "Removed provisioned: $($p.PackageName)"
      }
    }
  } catch {
    Write-Err "Provisioned removal failed: $($_.Exception.Message)"
  }
}

function Remove-LeftoverFoldersCurrentUser {
  $base = Join-Path $env:LOCALAPPDATA "Packages"
  Write-Info "Deleting leftover Snipping Tool folders for CURRENT user under: $base"
  if (-not (Test-Path $base)) { Write-Warn "Not found: $base"; return }

  $targets = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$PkgName*_$PublisherId" -or $_.Name -like "$PkgName*8wekyb3d8bbwe*" }

  if (-not $targets) { Write-Warn "No leftover folders found for current user."; return }

  foreach ($t in $targets) {
    if ($PSCmdlet.ShouldProcess($t.FullName, "Remove-Item -Recurse -Force")) {
      try {
        Remove-Item -Path $t.FullName -Recurse -Force -ErrorAction Stop
        Write-Info "Deleted: $($t.FullName)"
      } catch {
        Write-Warn "Could not delete $($t.FullName): $($_.Exception.Message)"
      }
    }
  }
}

function Remove-LeftoverFoldersAllProfiles {
  Write-Info "Deleting leftover Snipping Tool folders for ALL local profiles..."
  $usersRoot = "C:\Users"
  $skip = @("Public","Default","Default User","All Users")

  Get-ChildItem $usersRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $skip -notcontains $_.Name } | ForEach-Object {

      $pkgPath = Join-Path $_.FullName "AppData\Local\Packages"
      if (-not (Test-Path $pkgPath)) { return }

      $targets = Get-ChildItem -Path $pkgPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$PkgName*_$PublisherId" -or $_.Name -like "$PkgName*8wekyb3d8bbwe*" }

      foreach ($t in $targets) {
        if ($PSCmdlet.ShouldProcess($t.FullName, "Remove-Item -Recurse -Force")) {
          try {
            Remove-Item -Path $t.FullName -Recurse -Force -ErrorAction Stop
            Write-Info "Deleted: $($t.FullName)"
          } catch {
            Write-Warn "Could not delete $($t.FullName): $($_.Exception.Message)"
          }
        }
      }
    }
}

function Export-And-RemoveRegKey($regPath, $exportName){
  if (-not (Test-Path $regPath)) { return }

  Ensure-Dir $BackupDir
  $safeName = ($exportName -replace '[\\/:*?"<>| ]','_')
  $outFile = Join-Path $BackupDir "$safeName.reg"

  $regExePath = $regPath -replace "^HKCU:\\", "HKCU\" -replace "^HKLM:\\", "HKLM\" -replace "^HKCR:\\", "HKCR\" 
  $regExePath = $regExePath.TrimEnd('\')

  if ($PSCmdlet.ShouldProcess($regPath, "Export registry key to $outFile")) {
    try { & reg.exe export $regExePath $outFile /y | Out-Null; Write-Info "Backed up: $regPath -> $outFile" }
    catch { Write-Warn "Backup failed for ${regPath}: $($_.Exception.Message)" }
  }

  if ($PSCmdlet.ShouldProcess($regPath, "Remove registry key")) {
    try { Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop; Write-Info "Removed registry: $regPath" }
    catch { Write-Warn "Could not remove ${regPath}: $($_.Exception.Message)" }
  }
}

function Clean-RegistrySnippingTool {
  Write-Info "Cleaning Snipping Tool registry keys (Snipping Tool only)..."
  Ensure-Dir $BackupDir

  $keys = @(
    "HKCU:\Software\Microsoft\ScreenSketch",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.ScreenSketch_8wekyb3d8bbwe!App",
    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.ScreenSketch_8wekyb3d8bbwe"
  )

  if ($DeepRegistryClean) {
    $keys += "HKCU:\Software\Classes\ActivatableClasses\Package\Microsoft.ScreenSketch_8wekyb3d8bbwe"

    $actRoot = "HKCU:\Software\Classes\ActivatableClasses\Package"
    if (Test-Path $actRoot) {
      Get-ChildItem $actRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like "Microsoft.ScreenSketch_*_8wekyb3d8bbwe" } |
        ForEach-Object { $keys += $_.PSPath }
    }
  }

  foreach ($k in $keys) {
    Export-And-RemoveRegKey -regPath $k -exportName ("SnippingTool_" + ($k -replace '[:\\]','_'))
  }

  Write-Info "Registry cleanup complete. Backups stored in: $BackupDir"
}

function Remove-StartMenuShortcutsSnippingTool {
  # Removing stale shortcuts is a common way to clear lingering Start entries. 
  Write-Info "Removing Snipping Tool Start Menu shortcuts (.lnk) for current user and all users..."

  $paths = @(
    Join-Path $env:APPDATA     "Microsoft\Windows\Start Menu\Programs",
    Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
  )

  $wsh = New-Object -ComObject WScript.Shell

  foreach ($p in $paths) {
    if (-not (Test-Path $p)) { continue }

    $lnks = Get-ChildItem $p -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue

    foreach ($lnk in $lnks) {
      $match = $false

      # Name match (safe)
      if ($lnk.Name -match 'Snipping|ScreenSketch') { $match = $true }

      # Target match (more precise)
      try {
        $sc = $wsh.CreateShortcut($lnk.FullName)
        if ($sc.TargetPath -match 'SnippingTool\.exe|ScreenSketch') { $match = $true }
        if ($sc.Arguments  -match 'ScreenSketch|Microsoft\.ScreenSketch') { $match = $true }
      } catch { }

      if ($match) {
        if ($PSCmdlet.ShouldProcess($lnk.FullName, "Remove Snipping Tool shortcut")) {
          try {
            Remove-Item -Path $lnk.FullName -Force -ErrorAction Stop
            Write-Info "Deleted shortcut: $($lnk.FullName)"
          } catch {
            Write-Warn "Could not delete shortcut $($lnk.FullName): $($_.Exception.Message)"
          }
        }
      }
    }
  }
}

function Refresh-ShellNow {
  # Restarting StartMenu
  Write-Info "Refreshing Start Menu/Explorer processes..."
  if ($PSCmdlet.ShouldProcess("StartMenuExperienceHost", "Stop-Process -Force")) {
    Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
  }
  if ($PSCmdlet.ShouldProcess("explorer", "Stop-Process -Force")) {
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
  }
}

# --------------------- RUN ---------------------
Write-Info "Starting Snipping Tool removal + cleanup..."
Stop-SnippingToolProcs
Remove-AppxForCurrentUser

if ($AllUsers) { Remove-AppxForAllUsers }
if ($RemoveProvisioned) { Remove-Provisioned }

Remove-LeftoverFoldersCurrentUser
if ($PurgeAllProfiles) { Remove-LeftoverFoldersAllProfiles }

if ($PurgeRegistry) { Clean-RegistrySnippingTool }

if ($RemoveStartMenuShortcuts) { Remove-StartMenuShortcutsSnippingTool }
if ($RefreshShell) { Refresh-ShellNow }

Write-Info "Completed Snipping Tool removal + cleanup."
