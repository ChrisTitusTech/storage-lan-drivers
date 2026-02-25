# Define the root folder to scan (change this to your driver folder path)
$rootFolder = "C:\Users\chris\Downloads\SDIO_1.17.7.828\drivers"

# Counters
$deletedFiles = 0
$deletedFolders = 0
$incompatibleDriverCount = 0
$unsignedDriverCount = 0
$failedCount = 0

# Track folders already deleted to avoid double-processing
$deletedFolderPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# ----------------------------------------
# FUNCTION: Check if .inf is valid for Win11 64-bit
# ----------------------------------------
function Test-DriverCompatibility {
    param ([string]$InfPath)

    $content = Get-Content -Path $InfPath -ErrorAction SilentlyContinue
    if (-not $content) { return $false }

    $contentJoined = $content -join "`n"

    # Must have at least one section header targeting NTamd64 (64-bit Windows).
    # The version suffix (e.g. .6.1, .10.0) denotes MINIMUM OS — Win11 will still
    # match any NTamd64 section regardless of the minimum version specified.
    # Valid examples: [Models.NTamd64]  [Models.NTamd64.10.0]  [Models.NTamd64.6.1]
    $hasAmd64Section = $contentJoined -match '(?im)^\[[^\]]*\.NTamd64'

    # Also accept bare [NTamd64] or a Manufacturer line that lists NTamd64 as a target platform
    if (-not $hasAmd64Section) {
        $hasAmd64Section = $contentJoined -match '(?im)^\[NTamd64' -or
                           $contentJoined -match '(?im),\s*NTamd64(\.|\s|,|$)'
    }

    if (-not $hasAmd64Section) { return $false }

    # Reject if the ONLY architecture present is 32-bit (NTx86 sections, no NTamd64)
    # This is already covered above (we return $false when there's no NTamd64),
    # but make it explicit for clarity.
    $hasOnlyX86 = ($contentJoined -match '(?im)NTx86') -and (-not ($contentJoined -match '(?im)NTamd64'))
    if ($hasOnlyX86) { return $false }

    return $true
}

# ----------------------------------------
# FUNCTION: Check driver folder signature via .cat and .sys
# Returns: "Valid", "Unsigned", "NoCatalog", or "Missing"
# ----------------------------------------
function Get-DriverSignatureStatus {
    param ([string]$DriverFolder)

    $catFiles = Get-ChildItem -Path $DriverFolder -Filter "*.cat" -File -ErrorAction SilentlyContinue

    if ($catFiles) {
        $allValid = $true
        foreach ($cat in $catFiles) {
            $sig = Get-AuthenticodeSignature -FilePath $cat.FullName -ErrorAction SilentlyContinue
            if (-not $sig -or $sig.Status -ne "Valid") {
                Write-Host "  BAD CAT [$($sig.Status)]: $($cat.FullName)" -ForegroundColor DarkRed
                $allValid = $false
            }
        }
        if ($allValid) { return "Valid" }
        return "Unsigned"
    }

    # No .cat file - fall back to checking .sys directly
    $sysFiles = Get-ChildItem -Path $DriverFolder -Filter "*.sys" -File -ErrorAction SilentlyContinue
    if (-not $sysFiles) { return "Missing" }

    $allSigned = $true
    foreach ($sys in $sysFiles) {
        $sig = Get-AuthenticodeSignature -FilePath $sys.FullName -ErrorAction SilentlyContinue
        if (-not $sig -or $sig.Status -ne "Valid") {
            Write-Host "  BAD SYS [$($sig.Status)]: $($sys.FullName)" -ForegroundColor DarkRed
            $allSigned = $false
        }
    }
    if ($allSigned) { return "NoCatalog" }
    return "Unsigned"
}

# ----------------------------------------
# STEP 1: Delete unnecessary files
# ----------------------------------------
Write-Host "`n[STEP 1] Removing unnecessary files..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$extensionsToDelete = @(
    # Video files
    "*.avi", "*.mp4", "*.mkv", "*.mov", "*.wmv", "*.mpg", "*.mpeg",
    # Installers & packages
    "*.exe", "*.msi", "*.msp", "*.msm",
    # Documentation
    "*.txt", "*.rtf", "*.pdf", "*.html", "*.htm",
    # Help files
    "*.chm", "*.hlp",
    # Logs
    "*.log",
    # Installer config/manifest
    "*.xml",
    # Language & localisation
    "*.nls", "*.mui"
)

foreach ($extension in $extensionsToDelete) {
    $files = Get-ChildItem -Path $rootFolder -Filter $extension -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        # Preserve the WinUtil log so STEP 3 can parse it
        if ($file.FullName -eq (Join-Path $PSScriptRoot "WinUtil_Win11ISO.log")) {
            Write-Host "Skipping (reserved for STEP 3): $($file.FullName)" -ForegroundColor DarkGray
            continue
        }
        try {
            Write-Host "Deleting file: $($file.FullName)" -ForegroundColor Yellow
            Remove-Item -Path $file.FullName -Force
            $deletedFiles++
        }
        catch {
            Write-Host "FAILED to delete file: $($file.FullName)" -ForegroundColor Red
            $failedCount++
        }
    }
}

# ----------------------------------------
# STEP 2: Delete unnecessary folders
# ----------------------------------------
Write-Host "`n[STEP 2] Removing unnecessary folders..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$foldersToDelete = @(
    # Generic 32-bit architecture folders
    "x86", "i386", "Win32", "NTx86", "Allx86",
    # SDIO-convention 32-bit Windows-version folders (Win XP through Win10 x86)
    "5x86", "6x86", "7x86", "8x86", "81x86", "88x86", "10x86",
    # SDIO-convention 64-bit folders for old Windows only (XP x64 through Win 8.1 x64)
    # Win11 requires Win10-era drivers at minimum; these pre-Win10 x64 folders are obsolete
    "5x64", "6x64", "7x64", "8x64", "81x64",
    # Language/locale folders
    "en-US", "de-DE", "fr-FR", "es-ES", "it-IT", "ja-JP", "ko-KR",
    "zh-CN", "zh-TW", "pt-BR", "ru-RU", "nl-NL", "pl-PL", "tr-TR",
    "cs-CZ", "hu-HU", "sv-SE", "da-DK", "fi-FI", "nb-NO",
    # OEM software/UI folders
    "UI", "App", "Application", "ControlPanel", "Tray",
    "Help", "Docs", "Documentation", "Lang", "Language",
    "Installer", "Uninstall", "Redist", "Resources"
)

foreach ($folder in $foldersToDelete) {
    $dirs = Get-ChildItem -Path $rootFolder -Filter $folder -Recurse -Directory -ErrorAction SilentlyContinue

    foreach ($dir in $dirs) {
        try {
            Write-Host "Deleting folder: $($dir.FullName)" -ForegroundColor Yellow
            Remove-Item -Path $dir.FullName -Recurse -Force
            $null = $deletedFolderPaths.Add($dir.FullName)
            $deletedFolders++
        }
        catch {
            Write-Host "FAILED to delete folder: $($dir.FullName)" -ForegroundColor Red
            $failedCount++
        }
    }
}

# ----------------------------------------
# STEP 3: Remove drivers that failed DISM injection (WinUtil log)
# ----------------------------------------
Write-Host "`n[STEP 3] Checking WinUtil_Win11ISO.log for DISM injection failures..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$logPath = Join-Path $PSScriptRoot "WinUtil_Win11ISO.log"
if (Test-Path $logPath) {
    $logContent = Get-Content $logPath -ErrorAction SilentlyContinue
    $failedInfNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    for ($i = 0; $i -lt $logContent.Count; $i++) {
        $line = $logContent[$i]

        # Match DISM "Installing X of Y - <path>\driver.inf: <result>" lines
        if ($line -match 'Installing \d+ of \d+ - (.+\.inf):') {
            $infPath = $matches[1].Trim()
            $infName = [System.IO.Path]::GetFileName($infPath)

            # Look ahead up to 5 lines for a success confirmation
            $succeeded = $false
            for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $logContent.Count); $j++) {
                if ($logContent[$j] -match 'successfully installed') {
                    $succeeded = $true
                    break
                }
            }

            if (-not $succeeded) {
                $null = $failedInfNames.Add($infName)
                Write-Host "  DISM FAIL: $infName" -ForegroundColor Red
            }
        }
    }

    if ($failedInfNames.Count -eq 0) {
        Write-Host "  No DISM failures found in log." -ForegroundColor DarkGreen
    } else {
        foreach ($infName in $failedInfNames) {
            $matchingInfs = Get-ChildItem -Path $rootFolder -Filter $infName -Recurse -File -ErrorAction SilentlyContinue
            foreach ($inf in $matchingInfs) {
                $driverFolder = $inf.DirectoryName
                if ($deletedFolderPaths.Contains($driverFolder)) { continue }

                # Delete only the files sharing this driver's base name (e.g. e1c65x64.*)
                # rather than the whole folder, which may contain other valid drivers
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inf.Name)
                $siblingFiles = Get-ChildItem -Path $driverFolder -File -ErrorAction SilentlyContinue |
                    Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -ieq $baseName }

                foreach ($sibling in $siblingFiles) {
                    Write-Host "Deleting file (DISM failure): $($sibling.FullName)" -ForegroundColor Yellow
                    try {
                        Remove-Item -Path $sibling.FullName -Force
                        $deletedFiles++
                    } catch {
                        Write-Host "FAILED to delete file: $($sibling.FullName)" -ForegroundColor Red
                        $failedCount++
                    }
                }
                $incompatibleDriverCount++
            }
        }
    }
} else {
    Write-Host "  WinUtil_Win11ISO.log not found at: $logPath - skipping." -ForegroundColor DarkGray
}

# ----------------------------------------
# STEP 4: Check driver .inf compatibility (Win11 64-bit)
# ----------------------------------------
Write-Host "`n[STEP 4] Checking driver compatibility for Win11 64-bit..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$infFiles = Get-ChildItem -Path $rootFolder -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue

foreach ($inf in $infFiles) {
    $driverFolder = $inf.DirectoryName

    # Skip if already deleted in a previous step
    if ($deletedFolderPaths.Contains($driverFolder)) { continue }

    $isValid = Test-DriverCompatibility -InfPath $inf.FullName

    if (-not $isValid) {
        Write-Host "INCOMPATIBLE driver: $($inf.FullName)" -ForegroundColor Red
        try {
            Write-Host "Deleting folder: $driverFolder" -ForegroundColor Yellow
            Remove-Item -Path $driverFolder -Recurse -Force
            $null = $deletedFolderPaths.Add($driverFolder)
            $incompatibleDriverCount++
        }
        catch {
            Write-Host "FAILED to delete folder: $driverFolder" -ForegroundColor Red
            $failedCount++
        }
    }
    else {
        Write-Host "COMPAT OK: $($inf.FullName)" -ForegroundColor DarkGreen
    }
}

# ----------------------------------------
# STEP 5: Check driver signatures (.cat / .sys)
# Deletes any driver folder that is unsigned or has invalid catalog
# ----------------------------------------
Write-Host "`n[STEP 5] Checking driver signatures..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$infFiles = Get-ChildItem -Path $rootFolder -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue

foreach ($inf in $infFiles) {
    $driverFolder = $inf.DirectoryName

    # Skip if already deleted
    if ($deletedFolderPaths.Contains($driverFolder)) { continue }
    # Skip if folder no longer exists
    if (-not (Test-Path $driverFolder)) { continue }

    $status = Get-DriverSignatureStatus -DriverFolder $driverFolder

    switch ($status) {
        "Valid" {
            Write-Host "SIGNED OK: $driverFolder" -ForegroundColor Green
        }
        "Unsigned" {
            Write-Host "UNSIGNED - deleting: $driverFolder" -ForegroundColor Red
            try {
                Remove-Item -Path $driverFolder -Recurse -Force
                $null = $deletedFolderPaths.Add($driverFolder)
                $unsignedDriverCount++
            }
            catch {
                Write-Host "FAILED to delete: $driverFolder" -ForegroundColor Red
                $failedCount++
            }
        }
        "NoCatalog" {
            # Signed .sys but no .cat - DISM requires a .cat for offline injection
            Write-Host "NO CATALOG (cannot inject with DISM) - deleting: $driverFolder" -ForegroundColor Red
            try {
                Remove-Item -Path $driverFolder -Recurse -Force
                $null = $deletedFolderPaths.Add($driverFolder)
                $unsignedDriverCount++
            }
            catch {
                Write-Host "FAILED to delete: $driverFolder" -ForegroundColor Red
                $failedCount++
            }
        }
        "Missing" {
            # No .sys and no .cat - not a functional driver package
            Write-Host "NO DRIVER FILES (no .cat or .sys) - deleting: $driverFolder" -ForegroundColor DarkRed
            try {
                Remove-Item -Path $driverFolder -Recurse -Force
                $null = $deletedFolderPaths.Add($driverFolder)
                $unsignedDriverCount++
            }
            catch {
                Write-Host "FAILED to delete: $driverFolder" -ForegroundColor Red
                $failedCount++
            }
        }
    }
}

# ----------------------------------------
# STEP 6: Remove any empty folders left behind
# ----------------------------------------
Write-Host "`n[STEP 6] Cleaning up empty folders..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$emptyPasses = 0
do {
    $emptyFolders = Get-ChildItem -Path $rootFolder -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { (Get-ChildItem -Path $_.FullName -Recurse -File).Count -eq 0 }

    foreach ($emptyDir in $emptyFolders) {
        try {
            Write-Host "Removing empty folder: $($emptyDir.FullName)" -ForegroundColor DarkYellow
            Remove-Item -Path $emptyDir.FullName -Recurse -Force
        }
        catch {}
    }

    $emptyPasses++
} while ($emptyFolders.Count -gt 0 -and $emptyPasses -lt 10)

# ----------------------------------------
# SUMMARY
# ----------------------------------------
Write-Host "`n========================================"
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "  Files deleted                : $deletedFiles"
Write-Host "  Folders deleted (bloat)      : $deletedFolders"
Write-Host "  Incompatible drivers removed : $incompatibleDriverCount"
Write-Host "  Unsigned/uninjectible removed: $unsignedDriverCount"
Write-Host "  Failures                     : $failedCount"
Write-Host "========================================`n"