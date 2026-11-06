param(
    [string]$SourceDirectory = "games/rollback_fighter/fighter_assets/main_menu",
    [string]$GeneratedDirectory = "games/rollback_fighter/fighter_assets/main_menu/generated"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot $SourceDirectory))
$generatedRoot = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot $GeneratedDirectory))
if (-not $generatedRoot.StartsWith($sourceRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated output must remain inside the main_menu source directory."
}

$staticFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Filter "Screenshot*.png" | Sort-Object Name)
if ($staticFiles.Count -ne 1) {
    throw "Expected exactly one Screenshot*.png source image; found $($staticFiles.Count)."
}
$allGifFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Filter "*.gif" | Sort-Object Name)
$crestFiles = @($allGifFiles | Where-Object { $_.Name -like "Rotating Mexican-Soviet Crest Glitch*.gif" })
$gifFiles = @($allGifFiles | Where-Object { $_.Name -notlike "Rotating Mexican-Soviet Crest Glitch*.gif" })
if ($gifFiles.Count -eq 0) {
    throw "No GIF source footage was found."
}

function Convert-GifClip {
    param(
        [System.IO.FileInfo]$GifFile,
        [string]$OutputRoot
    )

    $clipId = [System.IO.Path]::GetFileNameWithoutExtension($GifFile.Name).ToLowerInvariant()
    $clipId = [System.Text.RegularExpressions.Regex]::Replace($clipId, "[^a-z0-9]+", "_").Trim("_")
    $clipDirectory = Join-Path $OutputRoot $clipId
    [System.IO.Directory]::CreateDirectory($clipDirectory) | Out-Null

    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($GifFile.FullName)
        $dimension = New-Object System.Drawing.Imaging.FrameDimension($image.FrameDimensionsList[0])
        $frameCount = $image.GetFrameCount($dimension)
        $delayBytes = $null
        try {
            $delayBytes = $image.GetPropertyItem(0x5100).Value
        } catch {
            $delayBytes = $null
        }
        $frames = @()
        for ($index = 0; $index -lt $frameCount; $index++) {
            $image.SelectActiveFrame($dimension, $index) | Out-Null
            $frameName = "frame_{0:D3}.png" -f $index
            $framePath = Join-Path $clipDirectory $frameName
            $bitmap = New-Object System.Drawing.Bitmap($image.Width, $image.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $graphics.DrawImage($image, 0, 0, $image.Width, $image.Height)
                } finally {
                    $graphics.Dispose()
                }
                $bitmap.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $bitmap.Dispose()
            }

            $durationSeconds = 0.1
            $delayOffset = $index * 4
            if ($null -ne $delayBytes -and ($delayOffset + 3) -lt $delayBytes.Length) {
                $hundredths = [BitConverter]::ToInt32($delayBytes, $delayOffset)
                $durationSeconds = [Math]::Max($hundredths, 1) / 100.0
            }
            $relativeFramePath = "res://games/rollback_fighter/fighter_assets/main_menu/generated/$clipId/$frameName"
            $frames += [ordered]@{
                path = $relativeFramePath
                duration_seconds = $durationSeconds
            }
        }
        return [ordered]@{
            clip_id = $clipId
            source_filename = $GifFile.Name
            width = $image.Width
            height = $image.Height
            frames = $frames
        }
    } catch {
        Write-Warning "Skipping unreadable GIF '$($GifFile.Name)': $($_.Exception.Message)"
        return $null
    } finally {
        if ($null -ne $image) {
            $image.Dispose()
        }
    }
}

[System.IO.Directory]::CreateDirectory($generatedRoot) | Out-Null
$clips = @()
foreach ($gifFile in $gifFiles) {
    $clip = Convert-GifClip -GifFile $gifFile -OutputRoot $generatedRoot
    if ($null -ne $clip) {
        $clips += $clip
    }
}
if ($clips.Count -eq 0) {
    throw "No GIF clips could be converted successfully."
}

$crest = $null
if ($crestFiles.Count -gt 1) {
    Write-Warning "Multiple crest GIFs found; using '$($crestFiles[0].Name)'."
}
if ($crestFiles.Count -gt 0) {
    $crest = Convert-GifClip -GifFile $crestFiles[0] -OutputRoot $generatedRoot
} else {
    Write-Warning "No Rotating Mexican-Soviet Crest Glitch GIF was found; the overlay will remain hidden."
}

$manifest = [ordered]@{
    format_version = 2
    static_image = "res://games/rollback_fighter/fighter_assets/main_menu/$($staticFiles[0].Name)"
    clips = $clips
    crest = $crest
}
$manifestPath = Join-Path $generatedRoot "playlist.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 8
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8WithoutBom)
Write-Output "Generated $($clips.Count) background clips and crest=$($null -ne $crest) at $generatedRoot"
