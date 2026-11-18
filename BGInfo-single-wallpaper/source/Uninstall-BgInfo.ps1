<#
.SYNOPSIS
    Uninstalls BGInfo and its scheduled task.

.DESCRIPTION
    Disables, stops, and removes the Apply-BGInfo scheduled task, then
    removes the four files deployed by Setup-BgInfo.ps1. Removes the
    installation directory only if it is empty.

    Preserves unrelated files, setup logs, and installer download caches.
    Does not restore users' previous wallpaper.

.NOTES
    Requires administrative privileges for uninstallation.

    Install Path:
        %ProgramData%\BGInfo

    Log:
        %Root%\Logs\BgInfo-Uninstall.log

    Scheduled Task:
        \Apply-BGInfo

.EXITCODES
    0 - Uninstallation completed successfully or BGInfo was already absent.
    1 - Uninstallation failed.
#>

#Requires -RunAsAdministrator

function Write-Log {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,
        [Parameter(Position = 1)]
        [string] $Component = "App Uninstall",
        [Parameter(Position = 2)]
        [ValidateSet(1, 2, 3)]
        [int] $Type = 1
    )

    $now = Get-Date
    $Time = $now.ToString('HH:mm:ss.ffffff', [System.Globalization.CultureInfo]::InvariantCulture)
    $Date = $now.ToString('MM-dd-yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
    $escapedMessage = [System.Security.SecurityElement]::Escape($Message).Replace('&apos;', "'")
    $logLine = ('<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">' `
        -f $escapedMessage, $Time, $Date, $Component, $Type)

    $dir = Split-Path -Path $logFile -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $logLine | Out-File -LiteralPath $logFile -Append -Encoding UTF8

    if ($InteractiveLogging) {
        switch ($Type) {
            1 { Write-Host $Message -ForegroundColor Gray }
            2 { Write-Host $Message -ForegroundColor Yellow }
            3 { Write-Host $Message -ForegroundColor Red }
        }
    }
}

$ErrorActionPreference = "Stop"

$logFile = "$env:Root\Logs\BgInfo-Setup.log"

# Ensure log directory exists
$logDir = Split-Path -Path $logFile -Parent
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$InteractiveLogging = $true

$InstallDir = Join-Path $env:PUBLIC 'BGInfo'
$TaskName = "Apply BGInfo"
$TaskPath = "\"

$Files = @(
    "Bginfo64.exe",
    "wallpaper.bgi",
    "Apply-BGInfo.ps1",
    "wallpaper.jpg"
)

try {

    Write-Log "Starting BGInfo uninstall process."

    $Task = Get-ScheduledTask -TaskPath $TaskPath |
        Where-Object { $_.TaskName -eq $TaskName }

    if ($Task) {
        Disable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath | Out-Null
        Write-Log "Disabled scheduled task: $TaskPath$TaskName"
        Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
        Write-Log "Stopped scheduled task: $TaskPath$TaskName"
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        Write-Log "Removed scheduled task: $TaskPath$TaskName"
    }
    else {
        Write-Log "Scheduled task is already absent: $TaskPath$TaskName"
    }

    foreach ($File in $Files) {
        $FilePath = Join-Path $InstallDir $File

        if (Test-Path -LiteralPath $FilePath) {
            Remove-Item -LiteralPath $FilePath -Force
            Write-Log "Removed file: $FilePath"
        }
        else {
            Write-Log "File is already absent: $FilePath"
        }
    }

    if (Test-Path -LiteralPath $InstallDir) {
        if (@(Get-ChildItem -LiteralPath $InstallDir -Force).Count -eq 0) {
            Remove-Item -LiteralPath $InstallDir -Force
            Write-Log "Removed empty installation directory: $InstallDir"
        }
        else {
            Write-Log "Preserved installation directory because it contains unrelated files: $InstallDir" -Type 2
        }
    }

    if (Get-ScheduledTask -TaskPath $TaskPath |
        Where-Object { $_.TaskName -eq $TaskName }) {
        throw "BGInfo scheduled task was not removed."
    }

    foreach ($File in $Files) {
        if (Test-Path -LiteralPath (Join-Path $InstallDir $File)) {
            throw "BGInfo file was not removed: $File"
        }
    }

    Write-Log "BGInfo uninstall process completed successfully."
    exit 0
}
catch {
    $FailureMessage = "BGInfo uninstallation failed: $($_.Exception.Message)"
    try {
        Write-Log $FailureMessage -Type 3
    }
    catch {
        Write-Error "Unable to write uninstall log: $($_.Exception.Message)" -ErrorAction Continue
    }
    Write-Error $FailureMessage -ErrorAction Continue
    exit 1
}
