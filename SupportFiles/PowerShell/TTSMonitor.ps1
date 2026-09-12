# TTSMonitor-v21.ps1 - announce helper app + version
# This script monitors the TTS queue folder and processes individual JSON files using an external TTS module.
# After processing, each JSON file is archived (moved to an Archive folder) rather than being removed.
# The ED TARGET script writes files named TTSMsg0000.json, TTSMsg0001.json, etc.
# The last 4 characters of the filename must match the TTSSeq key in the JSON file.
# On restart, the script will process any remaining files in order before resuming monitoring.

# Set the queue folder path
$queueFolder = "C:\Thrustmaster\ED_TargetScript_T16000\SupportFiles\Output\TTSQueue"

# Define the archive folder path (a subfolder named "Archive" within the queue folder)
$archiveFolder = Join-Path -Path $queueFolder -ChildPath "Archive"

# Create archive folder if it doesn't exist
if (!(Test-Path $archiveFolder)) {
    New-Item -ItemType Directory -Path $archiveFolder | Out-Null
}

# Import the TTS module
Import-Module "C:\Thrustmaster\ED_TargetScript_T16000\SupportFiles\PowerShell\Modules\TTS\TTS.psm1"

# Function: Test if a file is locked by trying to open it for read/write.
function Test-FileLocked {
    param (
        [string]$FilePath
    )
    try {
        $stream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        if ($stream) { $stream.Close() }
        return $false
    }
    catch {
        return $true
    }
}

# TTS startup
$voice = "Microsoft Zira Desktop"
$rate  = 1
$volume= 100
[TTS]::SpeakText("Text to speech monitor, version 21 loading.", $voice, $rate, $volume)
Start-Sleep -Milliseconds 500
[TTS]::SpeakText("Processing T T S queue.", $voice, $rate, $volume)

#Set the window title 
try {
    $host.UI.RawUI.WindowTitle = "TTS Monitor v21"
} catch {
    Write-Host "Could not set window title: $_"
}

Write-Host "Monitoring folder: $queueFolder for TTS message files..." -ForegroundColor Yellow

# Main processing loop
while ($true) {
    # Retrieve all TTS message JSON files and sort them in ascending sequence order.
    $files = Get-ChildItem -Path $queueFolder -Filter "TTSMsg*.json" | 
             Sort-Object { 
                 # Extract the 4-digit sequence number from the filename (assumes format: TTSMsgXXXX)
                 [int]($_.BaseName.Substring(6,4))
             }
    
    if ($files.Count -gt 0) {
        foreach ($file in $files) {
            # Wait until the file is not locked (retry up to 10 times)
            $attempts = 0
            while ((Test-FileLocked -FilePath $file.FullName) -and ($attempts -lt 10)) {
                Start-Sleep -Milliseconds 100
                $attempts++
            }
            if (Test-FileLocked -FilePath $file.FullName) {
                Write-Host "File $($file.Name) is locked after multiple attempts. Skipping for now." -ForegroundColor Red
                continue
            }

            # Check if the file is 5 minutes old or older. If yes, archive it and skip processing.

			$fileAge = (Get-Date) - $file.LastWriteTime
            if ($fileAge.TotalMinutes -ge 5) {
                Write-Host "File $($file.Name) is older than 5 minutes (Age: $([math]::Round($fileAge.TotalMinutes,2)) minutes), archiving it." -ForegroundColor Yellow
                try {
                    $destinationPath = Join-Path -Path $archiveFolder -ChildPath $file.Name
                    Move-Item $file.FullName -Destination $destinationPath -Force
                }
                catch {
                    Write-Host "Failed to archive $($file.Name): $_" -ForegroundColor Red
                }
                continue
            }
            
            # Attempt to read and parse the JSON file
            try {
                $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            }
            catch {
                Write-Host "Failed to read JSON from $($file.Name): $_. Skipping this file." -ForegroundColor Red
                continue
            }
            
            # Validate that the sequence in the filename matches the TTSSeq value in the JSON
            $expectedSeq = $file.BaseName.Substring(6,4)
            if ($json.TTSSeq -ne $expectedSeq) {
                Write-Host "WARNING: Sequence mismatch in file $($file.Name): Expected $expectedSeq, got $($json.TTSSeq)." -ForegroundColor DarkYellow
            }
            
            # Retrieve TTS parameters from the JSON
            $ttsString = $json.TTSString
            $ttsVoice  = $json.TTSVoice
            $ttsRate   = $json.TTSRate
            $ttsVolume = $json.TTSVolume

			$localtime = $((Get-Date).ToString('HH:mm:ss'))

            if ($ttsString) {
                Write-Host "TTS message ($localtime - Seq: $expectedSeq): $ttsString" -ForegroundColor Cyan
                try {
                    # Call the external TTS module with parameters from the JSON.
                    [TTS]::SpeakText($ttsString, $ttsVoice, $ttsRate, $ttsVolume)
                }
                catch {
                    Write-Host "Error during TTS processing: $_" -ForegroundColor Red
                }
            }
            else {
                Write-Host "No TTSMsg key found in $($file.Name)." -ForegroundColor Red
            }
            
            # Archive the processed file by moving it to the Archive folder.
            try {
			
				#	Remove file option...
                #Remove-Item $file.FullName -Force
                #Write-Host "Removed file: $($file.Name)" -ForegroundColor Yellow 

				#	Archive file option...
                $destinationPath = Join-Path -Path $archiveFolder -ChildPath $file.Name
                Move-Item $file.FullName -Destination $destinationPath -Force
            }
            catch {
                Write-Host "Failed to archive $($file.Name): $_" -ForegroundColor Red
            }
			
            if ($ttsString -match "GAME HALTED") {
                Write-Host "Game Halted detected, exiting in 20 seconds..." -ForegroundColor Yellow
				Start-Sleep -Milliseconds 20000
                Stop-Process -Id $PID -Force  # Forcefully kill script
            }
        }
    }
    else {
        # If no files are found, wait a short period before checking again
        Start-Sleep -Milliseconds 250
    }
}
