param(
    [string]$ModsPath,
    [string]$UserZomboidDirectory,
    [string]$presetName
)

$version = "v_1_0_0"
$modpackName = ""
$defaultPresetName = "Pain_${version}_$(Get-Date -Format "yyyyMMdd_HHmmss")$(if ($modpackName) { '_${modpackName}' } else { '' })"

if ([string]::IsNullOrEmpty($ModsPath)) {
    $ModsPath = Read-Host "Enter the mods path (default: D:\SteamLibrary\steamapps\workshop\content\108600)"
    if ([string]::IsNullOrEmpty($ModsPath)) { $ModsPath = "D:\SteamLibrary\steamapps\workshop\content\108600" }
}

if ([string]::IsNullOrEmpty($UserZomboidDirectory)) {
    $UserZomboidDirectory = Read-Host "Enter the Zomboid directory (default: $env:USERPROFILE\Zomboid\)"
    if ([string]::IsNullOrEmpty($UserZomboidDirectory)) { $UserZomboidDirectory = "$env:USERPROFILE\Zomboid" }
}

if ([string]::IsNullOrEmpty($PresetName)) {
    $PresetName = Read-Host "Enter preset name (default: $defaultPresetName)"
    if ([string]::IsNullOrEmpty($PresetName)) { $PresetName = $defaultPresetName }
}

$outputPath = Join-Path $UserZomboidDirectory "Lua\saved_modlists.txt"
$specialPath = Join-Path $UserZomboidDirectory "Workshop\ModTemplate\Contents"

function Parse-ModInfo([string]$ModInfoPath) {
    $modInfo = @{Id=$null;Name=$null;Require=@()}
    if (Test-Path -LiteralPath $ModInfoPath) {
        $content = Get-Content -LiteralPath $ModInfoPath -Encoding UTF8
        foreach ($line in $content) {
            $line = $line.Trim()
            if ($line -like "id=*") { $modInfo.Id = ($line -split '=', 2)[1].Trim() }
            elseif ($line -like "require=*") { $modInfo.Require = ($line -split '=', 2)[1].Trim() -split ',' | ForEach-Object { $_.Trim() } }
            elseif ($line -like "name=*") { $modInfo.Name = ($line -split '=', 2)[1].Trim() }
        }
    }
    return $modInfo
}

function Build-DependencyGraph([hashtable]$Mods) {
    $graph = @{}
    foreach ($modId in $Mods.Keys) { $graph[$modId] = $Mods[$modId].Require }
    return $graph
}

function Update-ProgressBar([int]$current, [int]$total) {
    $percent = [math]::Round(($current / $total) * 100)
    $barSize = 40
    $filled = [math]::Round(($current / $total) * $barSize)
    $bar = ("=" * $filled) + (" " * ($barSize - $filled))
    Write-Host -NoNewline "`r[$bar] $percent%"
}

function Sort-Topologically([hashtable]$DependencyGraph) {
    $sorted = New-Object System.Collections.ArrayList
    $visited = @{}
    $temporary = @{}
    
    function VisitNode([string]$node) {
        if ($visited[$node]) { return }
        if ($temporary[$node]) { throw "Circular dependency: $node" }
        $temporary[$node] = $true
        
        if ($DependencyGraph.ContainsKey($node)) {
            foreach ($dep in $DependencyGraph[$node]) {
                if ($dep -and $DependencyGraph.ContainsKey($dep) -and -not $visited[$dep]) {
                    VisitNode $dep
                }
            }
        }
        
        $temporary[$node] = $false
        $visited[$node] = $true
        [void]$sorted.Add($node)
    }
    
    $total = $DependencyGraph.Keys.Count
    $current = 0
    
    foreach ($modId in $DependencyGraph.Keys) {
        if (-not $visited[$modId] -and $modId -ne $null) {
            VisitNode $modId
        }
        $current++
        Update-ProgressBar $current $total
    }
    
    return @($sorted.ToArray())
}

Write-Host "Stage 1/4: Scanning mods in: $ModsPath"
if (-not (Test-Path $ModsPath)) { Write-Error "Mods directory not found: $ModsPath"; exit 1 }

$mods = @{}
$workshopFolders = Get-ChildItem -Path $ModsPath -Directory

try {
    $specialPathItem = Get-Item $specialPath -ErrorAction SilentlyContinue
    if ($specialPathItem) { $workshopFolders += $specialPathItem }
}
catch { Write-Warning "Special path not found: $specialPath" }

foreach ($folder in $workshopFolders) {
    $modPath = Join-Path $folder.FullName "mods"
    if (Test-Path $modPath) {
        $modDirs = Get-ChildItem -Path $modPath -Directory
        foreach ($modDir in $modDirs) {
            $modInfoPath = Join-Path $modDir.FullName "mod.info"
            if (Test-Path -LiteralPath $modInfoPath) {
                $modInfo = Parse-ModInfo -ModInfoPath $modInfoPath
                if ($modInfo.Id) {
                    $mods[$modInfo.Id] = @{Name=$modInfo.Name;Require=$modInfo.Require;Path=$modDir.FullName}
                }
            }
        }
    }
}

if ($mods.Count -eq 0) { Write-Warning "No mods found"; exit 0 }
Write-Host "`nStage 2/4: Found $($mods.Count) mods. Checking dependencies..."

$missingDependencies = @()
foreach ($modId in $mods.Keys) {
    foreach ($dep in $mods[$modId].Require) {
        if ($dep -and -not $mods.ContainsKey($dep)) {
            if ($missingDependencies -notcontains $dep) { $missingDependencies += $dep }
        }
    }
}

if ($missingDependencies.Count -gt 0) {
    Write-Host "`nMissing dependencies:" -ForegroundColor Red
    $missingDependencies | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host "`nStage 3/4: Resolving dependencies..."
$dependencyGraph = Build-DependencyGraph -Mods $mods

try {
    Write-Host "Sorting mods by dependencies: "
    $sortedMods = Sort-Topologically -DependencyGraph $dependencyGraph
    Write-Host "`n`nDependencies resolved successfully!"
    
    $sortedMods = $sortedMods | Where-Object { $_ -ne $null -and $mods.ContainsKey($_) }
    Write-Host "Stage 4/4: Adding mod preset output file..."
    
    $outputDir = Split-Path $outputPath -Parent
    if (!(Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force }
    
    $outputContent = "${PresetName}:" + ($sortedMods -join ";")
    $outputContent | Out-File -FilePath $outputPath -Append -Encoding UTF8
    
    Write-Host "`nMods preset saved: $PresetName"
    Write-Host "All done! $($mods.Count) mods processed successfully."
}
catch { Write-Error "Error resolving dependencies: $($_.Exception.Message)" }