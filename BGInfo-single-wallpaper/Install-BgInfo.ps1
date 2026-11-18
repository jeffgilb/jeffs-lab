<#
.SYNOPSIS
    Installs and configures BGInfo with a corporate wallpaper.

.DESCRIPTION
    Downloads and installs the Microsoft Sysinternals BGInfo utility,
    deploys the BGInfo configuration and corporate wallpaper, and creates
    a scheduled task to refresh the wallpaper and apply BGInfo at user
    logon.

    The hosted wallpaper is refreshed only when the source image changes,
    using a SHA256 hash comparison.

.NOTES
    Requires administrative privileges for installation.
    BGInfo runs in the logged-on user's context through a scheduled task.

    Install Path:
        %ProgramData%\BGInfo

    Log:
        %Root%\Logs\BgInfo-Setup.log

    Scheduled Task:
        \Apply-BGInfo

    Required Source File:
        wallpaper.bgi

.EXITCODES
    0 - Installation completed successfully.
    1 - Installation failed.
#>

function Write-Log {

    #-- THIS FUNCTION REQUIRES THE FOLLOWING BE DECLARED IN THE MAIN SCRIPT --#
    # $logPath                                                              
    # $logName                                                              
    #-------------------------------------------------------------------------#

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]    [ValidateNotNullOrEmpty()]  [string] $Message,
        [Parameter(Mandatory = $false, Position = 1)]   [string] $Component = "App Install",
        [Parameter(Mandatory = $false, Position = 2)]   [ValidateSet(1, 2, 3)]      [int] $Type = 1,
        [Parameter(Mandatory = $false)]                 [switch] $StdOut
    )
  # Capture once to avoid drift between Time/Date
    $now = Get-Date 
    $Time = $now.ToString('HH:mm:ss.ffffff', [System.Globalization.CultureInfo]::InvariantCulture)
    $Date = $now.ToString('MM-dd-yyyy',      [System.Globalization.CultureInfo]::InvariantCulture)
  # Escape message for CMTrace payload (XML-like). SecurityElement.Escape handles &, <, >, " (quotes) safely
    $escapedMessage = [System.Security.SecurityElement]::Escape($Message).Replace('&apos;', "'")
  # Identify if it was a function that called Log and make it the component"
    $scriptFullPath = $PSCommandPath ; $scriptName = Split-Path -Path $scriptFullPath -Leaf
    $caller = (Get-PSCallStack)[1].Command
    if (-not ($caller -eq $scriptName)){ $Component = $caller }  
  # Build CMTrace entry (keep empty attributes as per CMTrace spec)
    $logLine = ('<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">' `
                -f $escapedMessage, $Time, $Date, $Component, $Type)
    try { 
      # Write the log entry
        $dir = Split-Path -Path  $logFile -Parent 
      # Ensure log directory exists
        New-Item -ItemType Directory -Path $dir -Force | Out-Null 
      # Write message to the log file
        $logLine | Out-File -LiteralPath $logFile -Append -Encoding UTF8
      # Add message to detection results sent to the Intune admin center  
        if ($StdOut) { $detectionOutput.Add($Message) }
      # Write all log lines to console for interactive testing/transcript capture
        if ($InteractiveLogging) {
            switch ($Type) {
                1 { Write-Host $Message -ForegroundColor Gray }
                2 { Write-Host $Message -ForegroundColor Yellow }
                3 { Write-Host $Message -ForegroundColor Red }
                default { Write-Host $Message }
            }
        }
    }
    catch { # If writing fails write error
        Write-Error -Message ("Failed to write log to '{0}': {1}" -f $logFile, $_.Exception.Message)
        return
    }
}

#Requires -RunAsAdministrator

#----------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------

#***** UPDATE THIS TO MATCH THE SAME .JPG URL YOU USE IF YOU'RE USING THE PERSONALIZATION CSP POLICY *****

$WallpaperUrl = "https://github.com/jeffgilb/jeffs-lab/blob/main/media/img0.jpg?raw=true"

#----------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$logFile = "$env:Root\Logs\BgInfo-Setup.log"

# Ensure log directory exists
$logDir = Split-Path -Path $logFile -Parent

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$InteractiveLogging 	= $true
$InstallDir 		= "$env:ProgramData\BGInfo"
$DownloadUrl 		= "https://download.sysinternals.com/files/BGInfo.zip"
$TempRoot 		= Join-Path $env:TEMP "BGInfoInstall"
$ZipFile  		= Join-Path $TempRoot "BGInfo.zip"
$Wallpaper 		= Join-Path $InstallDir "wallpaper.jpg"
$TaskName 		= "Apply BGInfo"

try {

    Write-Log "Starting BGInfo setup process."
    #-----------------------------------------------
    # Create directories
    #-----------------------------------------------

    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    Write-Log "Created installation directory: $InstallDir"
    New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null
    Write-Log "Created temporary directory: $TempRoot"

    #-----------------------------------------------
    # Download official Microsoft Sysinternals package
    #-----------------------------------------------

    Invoke-WebRequest `
        -Uri $DownloadUrl `
        -OutFile $ZipFile `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Log "Downloading BGInfo package from $DownloadUrl"
    # Extract
    Expand-Archive `
        -Path $ZipFile `
        -DestinationPath $TempRoot `
        -Force
    Write-Log "Extracted BGInfo package to $TempRoot"

    # Install 64-bit executable
    Copy-Item `
        -Path "$TempRoot\Bginfo64.exe" `
        -Destination "$InstallDir\Bginfo64.exe" `
        -Force
    Write-Log "Installed 64-bit BGInfo executable to $InstallDir"

    #-----------------------------------------------
    # Download hosted wallpaper
    #-----------------------------------------------

    Invoke-WebRequest `
        -Uri $WallpaperUrl `
        -OutFile $Wallpaper `
        -UseBasicParsing `
        -TimeoutSec 30 `
        -ErrorAction Stop
    Write-Log "Downloaded wallpaper from $WallpaperUrl to $Wallpaper"

    #-----------------------------------------------
    # Copy application files
    #-----------------------------------------------
  
    $Files = @(
        "wallpaper.bgi"
    )

    foreach ($File in $Files) {

        Copy-Item `
            -Path "$PSScriptRoot\$File" `
            -Destination "$InstallDir\$File" `
            -Force
        Write-Log "Copied $File to $InstallDir"
    }

    #-----------------------------------------------
    # Standard users need to overwrite only
    # the wallpaper source image
    # S-1-5-32-545 = BUILTIN\Users
    #-----------------------------------------------

    & icacls.exe `
        "$InstallDir\wallpaper.jpg" `
        /grant '*S-1-5-32-545:(M)' | Out-Null
    Write-Log "Granted modify permissions to BUILTIN\Users for $InstallDir\wallpaper.jpg so they can update the wallpaper if it changes"

    
    #-----------------------------------------------
    # Create Apply-BGInfo.ps1
    #-----------------------------------------------

    $ApplyScript = @'
$ErrorActionPreference = "Stop"

$BgInfoRoot = "$env:ProgramData\BGInfo"

$BgInfo    = "$BgInfoRoot\Bginfo64.exe"
$Config    = "$BgInfoRoot\wallpaper.bgi"
$Wallpaper = "$BgInfoRoot\wallpaper.jpg"

$WallpaperUrl = @@WALLPAPER_URL@@

$TempImage = Join-Path `
    $env:TEMP `
    "wallpaper-$PID.jpg"

try {

    #-----------------------------------------------
    # Download hosted wallpaper
    #-----------------------------------------------

    Invoke-WebRequest `
        -Uri $WallpaperUrl `
        -OutFile $TempImage `
        -UseBasicParsing `
        -TimeoutSec 10 `
        -ErrorAction Stop


    #-----------------------------------------------
    # Calculate hosted image hash
    #-----------------------------------------------

    $RemoteHash = (
        Get-FileHash `
            -Path $TempImage `
            -Algorithm SHA256
    ).Hash


    #-----------------------------------------------
    # Calculate local image hash
    #-----------------------------------------------

    if (Test-Path $Wallpaper) {

        $LocalHash = (
            Get-FileHash `
                -Path $Wallpaper `
                -Algorithm SHA256
        ).Hash

    }
    else {

        $LocalHash = $null
    }


    #-----------------------------------------------
    # Replace wallpaper if it changed
    #-----------------------------------------------

    if ($RemoteHash -ne $LocalHash) {

        Copy-Item `
            -Path $TempImage `
            -Destination $Wallpaper `
            -Force
    }

}
catch {

    # Don't prevent BGInfo from running if the
    # hosted image can't be reached.

    Write-Warning "Unable to refresh corporate wallpaper: $($_.Exception.Message)"
}
finally {

    Remove-Item `
        -Path $TempImage `
        -Force `
        -ErrorAction SilentlyContinue

}


#-----------------------------------------------
# Apply-BGInfo
#-----------------------------------------------

if (
    (Test-Path $BgInfo) -and
    (Test-Path $Config) -and
    (Test-Path $Wallpaper)
) {

    & $BgInfo `
        $Config `
        /timer:0 `
        /silent `
        /nolicprompt

}
else {

    Write-Warning "Required BGInfo files were not found."
}
'@

    $QuotedWallpaperUrl = "'" + $WallpaperUrl.Replace("'", "''") + "'"
    $ApplyScript = $ApplyScript.Replace("@@WALLPAPER_URL@@", $QuotedWallpaperUrl)

    Set-Content `
        -LiteralPath "$InstallDir\Apply-BGInfo.ps1" `
        -Value $ApplyScript `
        -Encoding UTF8
    
    #-----------------------------------------------
    # Create scheduled task
    #
    # AtLogOn + InteractiveToken means the task runs
    # in the context of the user logging on.
    #-----------------------------------------------

    $PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $Action = New-ScheduledTaskAction `
        -Execute $PowerShell `
        -Argument "-WindowStyle Hidden -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$InstallDir\Apply-BGInfo.ps1`""

    $LogonTrigger = New-ScheduledTaskTrigger -AtLogOn

    #-----------------------------------------------
    # Interactive user principal
    #-----------------------------------------------

    $Principal = New-ScheduledTaskPrincipal `
        -GroupId "BUILTIN\Users" `
        -RunLevel Limited

    #-----------------------------------------------
    # Task settings
    #-----------------------------------------------

    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    #-----------------------------------------------
    # Register / replace task
    #-----------------------------------------------

    Register-ScheduledTask `
        -TaskPath "\" `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $LogonTrigger `
        -Principal $Principal `
        -Settings $Settings `
        -Description "Refreshes device wallpaper and applies BGInfo at logon." `
        -Force | Out-Null

    #-----------------------------------------------
    # Validation
    #-----------------------------------------------

    if (-not (Test-Path "$InstallDir\Bginfo64.exe")) {
        throw "Bginfo64.exe was not installed."
    } else {
        Write-Log "Bginfo64.exe was installed successfully."
    }

    if (-not (Get-ScheduledTask -TaskName $TaskName -TaskPath "\" -ErrorAction SilentlyContinue)) {
        throw "BGInfo scheduled task was not created."
    } else {
        Write-Log "BGInfo scheduled task was created successfully."
    }

    Write-Log "BGInfo setup process completed successfully."
    exit 0
}
catch {

    Write-Log "BGInfo installation failed: $($_.Exception.Message)"
    exit 1
}