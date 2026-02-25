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

    $is64Bit = $false
    $contentJoined = $content -join "`n"

    foreach ($line in $content) {
        if ($line -match "NTamd64|NTx64|amd64|\.10\.0\.\d{5}") {
            $is64Bit = $true
        }
    }

    $isGenericAmd64 = $contentJoined -match "\[.*NTamd64.*\]"
    $noOldOSOnly = -not ($contentJoined -match "NTx86" -and -not ($contentJoined -match "NTamd64"))

    return ($is64Bit -or $isGenericAmd64) -and $noOldOSOnly
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
    # 32-bit architecture folders
    "x86", "i386", "Win32",
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
# STEP 3: Check driver .inf compatibility (Win11 64-bit)
# ----------------------------------------
Write-Host "`n[STEP 3] Checking driver compatibility for Win11 64-bit..." -ForegroundColor Cyan
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
# STEP 4: Check driver signatures (.cat / .sys)
# Deletes any driver folder that is unsigned or has invalid catalog
# ----------------------------------------
Write-Host "`n[STEP 4] Checking driver signatures..." -ForegroundColor Cyan
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
# STEP 5: Remove any empty folders left behind
# ----------------------------------------
Write-Host "`n[STEP 5] Cleaning up empty folders..." -ForegroundColor Cyan
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