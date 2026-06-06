# Post-export check: required runtime Markdown paths must appear in main.pck.
# Usage: powershell -File scripts/verify_export_pck.ps1 [-PckPath dist\main.pck]

param(
    [string]$PckPath = (Join-Path $PSScriptRoot "..\dist\main.pck")
)

$ErrorActionPreference = "Stop"
$PckPath = (Resolve-Path -LiteralPath $PckPath -ErrorAction Stop).Path

$required = @(
    "src/novel_config/narrative_turn.md",
    "src/novel_config/narrative_archive_title.md",
    "src/novel_config/baseConfig.md",
    "src/novel_config/skillConfig.md",
    "src/novel_config/worldBuild.md",
    "ai_config/AiSkills/narrative_context_compact.md",
    "ai_config/AiSkills/dynamic_add.routing.md"
)

$bytes = [System.IO.File]::ReadAllBytes($PckPath)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

$missing = @()
foreach ($path in $required) {
    if ($text -notmatch [regex]::Escape($path)) {
        $missing += $path
    }
}

if ($missing.Count -gt 0) {
    $msg = "PCK missing runtime Markdown: " + ($missing -join ", ")
    $msg += ". Check export_presets.cfg include_filter and re-export."
    Write-Error $msg
    exit 1
}

Write-Host ("OK: {0} contains {1} required .md paths." -f $PckPath, $required.Count)
exit 0
