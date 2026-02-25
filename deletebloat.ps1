# Define the root folder to scan (change this to your driver folder path)
$rootFolder = "C:\Users\chris\Downloads\SDIO_1.17.7.828\drivers"

# Counters
$deletedFiles = 0
$deletedFolders = 0
$invalidDriverCount = 0
$failedCount = 0

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
            $deletedFolders++
        }
        catch {
            Write-Host "FAILED to delete folder: $($dir.FullName)" -ForegroundColor Red
            $failedCount++
        }
    }
}

# ----------------------------------------
# STEP 3: Check driver .inf compatibility
# ----------------------------------------
Write-Host "`n[STEP 3] Checking driver compatibility for Win11 64-bit..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

$infFiles = Get-ChildItem -Path $rootFolder -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue

foreach ($inf in $infFiles) {
    $isValid = Test-DriverCompatibility -InfPath $inf.FullName

    if (-not $isValid) {
        Write-Host "INCOMPATIBLE driver: $($inf.FullName)" -ForegroundColor Red
        $driverFolder = $inf.DirectoryName
        try {
            Write-Host "Deleting folder: $driverFolder" -ForegroundColor Yellow
            Remove-Item -Path $driverFolder -Recurse -Force
            $invalidDriverCount++
        }
        catch {
            Write-Host "FAILED to delete folder: $driverFolder" -ForegroundColor Red
            $failedCount++
        }
    }
    else {
        Write-Host "OK: $($inf.FullName)" -ForegroundColor Green
    }
}

# ----------------------------------------
# STEP 4: Remove any empty folders left behind
# ----------------------------------------
Write-Host "`n[STEP 4] Cleaning up empty folders..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

# Loop multiple times to catch nested empty folders
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
Write-Host "  Files deleted            : $deletedFiles"
Write-Host "  Folders deleted          : $deletedFolders"
Write-Host "  Incompatible drivers removed : $invalidDriverCount"
Write-Host "  Failures                 : $failedCount"
Write-Host "========================================`n"