#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillsTarget = Join-Path $HOME ".claude\skills"
$ExternalsDir = Join-Path $RepoDir "_externals"

New-Item -ItemType Directory -Force -Path $SkillsTarget | Out-Null
New-Item -ItemType Directory -Force -Path $ExternalsDir | Out-Null

function Link-Dir {
    param([string]$Source, [string]$Target)
    if (Test-Path -LiteralPath $Target) {
        $existing = Get-Item -LiteralPath $Target -Force
        if ($existing.LinkType -and $existing.Target -contains $Source) {
            Write-Host "  [skip]  $(Split-Path -Leaf $Target) (already linked)"
            return
        }
        Write-Host "  [warn]  $Target exists; skipping"
        return
    }
    # Junction works for directories without admin rights
    New-Item -ItemType Junction -Path $Target -Target $Source | Out-Null
    Write-Host "  [ok]    $(Split-Path -Leaf $Target)"
}

# 1. Local skills
$LocalSkills = Join-Path $RepoDir "skills"
if (Test-Path -LiteralPath $LocalSkills) {
    Write-Host "==> Linking local skills..."
    Get-ChildItem -Directory -LiteralPath $LocalSkills | ForEach-Object {
        Link-Dir -Source $_.FullName -Target (Join-Path $SkillsTarget $_.Name)
    }
}

# 2. External skills
$ExtFile = Join-Path $RepoDir "externals.txt"
if (Test-Path -LiteralPath $ExtFile) {
    Write-Host "==> Installing external skills..."
    Get-Content -LiteralPath $ExtFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $parts = $line -split '\|'
        if ($parts.Length -ne 3) { return }
        $repo, $path, $name = $parts | ForEach-Object { $_.Trim() }

        $repoBase = [System.IO.Path]::GetFileNameWithoutExtension($repo)
        $repoDir  = Join-Path $ExternalsDir $repoBase

        if (-not (Test-Path -LiteralPath (Join-Path $repoDir ".git"))) {
            Write-Host "  [clone] $repo"
            git clone --depth 1 $repo $repoDir | Out-Null
        } else {
            Push-Location $repoDir
            try { git pull --ff-only --quiet 2>$null; Write-Host "  [pull]  $repoBase" }
            catch { Write-Host "  [warn]  pull failed: $repoBase" }
            finally { Pop-Location }
        }

        $src = Join-Path $repoDir $path
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "  [error] missing path: $src"; return
        }
        Link-Dir -Source $src -Target (Join-Path $SkillsTarget $name)
    }
}

function Has-Claude { $null -ne (Get-Command claude -ErrorAction SilentlyContinue) }

# 3. Plugin marketplaces
$MktFile = Join-Path $RepoDir "marketplaces.txt"
if (Test-Path -LiteralPath $MktFile) {
    if (Has-Claude) {
        Write-Host "==> Registering plugin marketplaces..."
        Get-Content -LiteralPath $MktFile | ForEach-Object {
            $src = $_.Trim()
            if (-not $src -or $src.StartsWith('#')) { return }
            $output = (claude plugin marketplace add $src 2>&1) -join "`n"
            if ($output -match '(?i)already|exists') {
                Write-Host "  [skip]  $src"
            } else {
                Write-Host "  [ok]    $src"
            }
        }
    } else {
        Write-Host "==> Skipping marketplaces ('claude' CLI not found)"
    }
}

# 4. Plugins
$PlgFile = Join-Path $RepoDir "plugins.txt"
if (Test-Path -LiteralPath $PlgFile) {
    if (Has-Claude) {
        Write-Host "==> Installing plugins..."
        Get-Content -LiteralPath $PlgFile | ForEach-Object {
            $spec = $_.Trim()
            if (-not $spec -or $spec.StartsWith('#')) { return }
            $output = (claude plugin install $spec 2>&1) -join "`n"
            if ($output -match '(?i)already') {
                Write-Host "  [skip]  $spec"
            } else {
                Write-Host "  [ok]    $spec"
            }
        }
    } else {
        Write-Host "==> Skipping plugins ('claude' CLI not found)"
    }
}

Write-Host "==> Done. Skills: $SkillsTarget"
