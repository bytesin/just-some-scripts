# Define the path to the GameUserSettings.ini file
$iniPath = "$env:LOCALAPPDATA\Ride\Saved\Config\Windows\GameUserSettings.ini"

# Check if the file exists
if (!(Test-Path $iniPath)) {
    Write-Host "GameUserSettings.ini file not found at $iniPath" -ForegroundColor Red
    Write-Host "Please make sure you have launched the game at least once." -ForegroundColor Yellow
    exit
}

Write-Host "GameUserSettings.ini file found at $iniPath" -ForegroundColor Green

# Prompt user for desired number of players
do {
    $playerCount = Read-Host "Enter the number of players you wish to increase to (5-6 recommended)"
    if ($playerCount -match "^\d+$") {
        $playerCount = [int]$playerCount
        break
    } else {
        Write-Host "Please enter a valid number." -ForegroundColor Red
    }
} while ($true)

# Check if player count is <= 4 (default)
if ($playerCount -le 4) {
    Write-Host "The game supports 4 players by default. No changes needed." -ForegroundColor Yellow
    exit
}

# Check if player count is > 6 (base game seats)
if ($playerCount -gt 6) {
    Write-Host "Warning: There are only 6 seats in the base game." -ForegroundColor Red
    $continue = Read-Host "Do you still want to proceed? (Y/n) [Y]"
    if ($continue -eq 'n' -or $continue -eq 'N') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit
    }
    # User wants to continue (default is Y)
}

# Read the current content of the file
$content = Get-Content $iniPath -Raw

# Check if the [/script/engine.gamesession] section already exists
if ($content -match '\[\/script\/engine\.gamesession\]') {
    # Update existing MaxPlayers value if it exists
    if ($content -match 'MaxPlayers=\d+') {
        $content = $content -replace 'MaxPlayers=\d+', "MaxPlayers=$playerCount"
        Write-Host "Updated MaxPlayers to $playerCount in existing section." -ForegroundColor Green
    } else {
        # Add MaxPlayers to existing section
        $content = $content -replace '(\[\/script\/engine\.gamesession\]\s*)', "`$1MaxPlayers=$playerCount`n"
        Write-Host "Added MaxPlayers=$playerCount to existing section." -ForegroundColor Green
    }
} else {
    # Add the new section with the MaxPlayers setting
    $content += "`n[/script/engine.gamesession]`n"
    $content += "MaxPlayers=$playerCount`n"
    Write-Host "Added [/script/engine.gamesession] section with MaxPlayers=$playerCount" -ForegroundColor Green
}

# Write the updated content back to the file
Set-Content $iniPath -Value $content

Write-Host "Successfully updated the player limit to $playerCount!" -ForegroundColor Green