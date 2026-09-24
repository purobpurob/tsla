<#
.SYNOPSIS
    Opretter en planlagt opgave i Windows der kører Update-TSLA.ps1 på hverdage.
    Køres én gang som den bruger der har Git-adgang til GitHub.

.PARAMETER Time
    Lokalt tidspunkt. Standard 22:45 dansk tid, lidt efter at NYSE lukker (22:00 dansk tid det meste af året).
#>
param(
    [string]$Time = '22:45',
    [string]$TaskName = 'TSLA Swing Trader update'
)

$script = Join-Path $PSScriptRoot 'Update-TSLA.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Henter TSLA data, beregner indikatorer og pusher JSON til GitHub Pages' -Force
Write-Host "Opgaven '$TaskName' er oprettet og kører hverdage kl. $Time"
