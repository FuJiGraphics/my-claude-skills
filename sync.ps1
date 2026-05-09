#Requires -Version 5.1
# Pull current local Claude Code state back into the repo. See sync.sh for details.
$ErrorActionPreference = 'Stop'

$RepoDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillsDir    = Join-Path $RepoDir "skills"
$SkillsTarget = Join-Path $HOME ".claude\skills"

New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null

# --- 1. Adopt unmanaged skills ---
Write-Host "==> Scanning $SkillsTarget for unmanaged skills..."
if (Test-Path -LiteralPath $SkillsTarget) {
    Get-ChildItem -Force -LiteralPath $SkillsTarget | ForEach-Object {
        $entry = $_
        if ($entry.LinkType) {
            Write-Host "  [skip]  $($entry.Name) (already linked)"
            return
        }
        if (-not $entry.PSIsContainer) {
            Write-Host "  [warn]  $($entry.Name) is not a directory; skipping"
            return
        }
        $repoPath = Join-Path $SkillsDir $entry.Name
        if (Test-Path -LiteralPath $repoPath) {
            Write-Host "  [warn]  skills/$($entry.Name) already exists; resolve manually"
            return
        }
        Move-Item -LiteralPath $entry.FullName -Destination $repoPath
        New-Item -ItemType Junction -Path $entry.FullName -Target $repoPath | Out-Null
        Write-Host "  [adopt] $($entry.Name) -> skills/$($entry.Name)"
    }
}

function Append-Unique {
    param([string]$File, [string]$Line)
    if (Test-Path -LiteralPath $File) {
        $content = Get-Content -LiteralPath $File
        if ($content -contains $Line) {
            Write-Host "  [skip]  $Line"
            return
        }
    }
    if (-not (Test-Path -LiteralPath $File)) { New-Item -ItemType File -Path $File | Out-Null }
    Add-Content -LiteralPath $File -Value $Line
    Write-Host "  [add]   $Line"
}

function Has-Claude { $null -ne (Get-Command claude -ErrorAction SilentlyContinue) }

# --- 2. Sync marketplaces.txt ---
$MktFile = Join-Path $RepoDir "marketplaces.txt"
if (Has-Claude) {
    Write-Host "==> Syncing marketplaces.txt from ``claude plugin marketplace list --json``..."
    $raw = (claude plugin marketplace list --json 2>$null) -join "`n"
    $items = @()
    try { $items = $raw | ConvertFrom-Json } catch { $items = @() }
    foreach ($m in $items) {
        $entry = $null
        switch ($m.source) {
            'github' { $entry = $m.repo }
            'git'    { $entry = $m.url }
            'local'  { $entry = $m.path }
            default  { if ($m.url) { $entry = $m.url } }
        }
        if ($entry) { Append-Unique -File $MktFile -Line $entry }
    }
}

# --- 3. Sync plugins.txt ---
$PlgFile = Join-Path $RepoDir "plugins.txt"
if (Has-Claude) {
    Write-Host "==> Syncing plugins.txt from ``claude plugin list --json``..."
    $raw = (claude plugin list --json 2>$null) -join "`n"
    $items = @()
    try { $items = $raw | ConvertFrom-Json } catch { $items = @() }
    if ($items.Count -eq 0) {
        Write-Host "  [info]  no plugins installed"
    } else {
        foreach ($p in $items) {
            $name   = if ($p.name) { $p.name } else { $p.plugin }
            if (-not $name) { continue }
            $market = if ($p.marketplace) { $p.marketplace } else { $p.source }
            $line   = if ($market) { "$name@$market" } else { $name }
            Append-Unique -File $PlgFile -Line $line
        }
    }
}

Write-Host "==> Done. Review with ``git diff`` and commit."
