#requires -Version 7.4
# Test-ProceduralDirectGenerator.ps1
# Direct Procedural Generator Test:
# Validates synthesizing speech directly into 512-channel x using
# Subspace Coordinate Projection, completely bypassing the Neural Decoder,
# and rendering through the Hexagon Generator Tail with Pinned VoiceBase AdaIN.

using module ../student/SpeechPerformanceScore.psm1

param(
    [string] $Voice = 'af_heart',
    [string] $OutputDir = 'build/procedural-direct-generator',
    [int] $Rank = 32,
    [switch] $PlayOnPhone
)

$ErrorActionPreference = 'Stop'
$root = 'C:\dev\kokoro-hexagon'
$out = [IO.Path]::GetFullPath((Join-Path $root $OutputDir))
$null = [IO.Directory]::CreateDirectory($out)

Write-Host "=========================================================="
Write-Host "    DIRECT PROCEDURAL GENERATION: DECODER BYPASS TEST     "
Write-Host "=========================================================="

# 1. Load Ground Truth Corpus Evidence for Subspace Extraction
Write-Host "`n--- Loading Retained Corpus Observation (Gutenberg/11) ---"
$bank = Join-Path $root 'data/source-bank'
$field = & (Join-Path $root 'student/Open-StudentSpeechInvestigation.ps1') -BankPath $bank -SourceIdentity 'Gutenberg/11'
$t = $field.Comparisons[0].Teacher
$handoff = $t.StockExecution.DecoderHandoff

$features = [float[]]$handoff.GeneratorFeatures.Read() # 512 channels * totalTicks
$pitch = [single[]]$handoff.GeneratorPitch.Read()
$style = [float[]]$handoff.AcousticStyle.Read()
$rawUniform = [float[]]$handoff.UniformDraw.Read()
$rawHarmonic = [float[]]$handoff.HarmonicDraw.Read()
$rawExtra = [float[]]$handoff.ExtraDraw.Read()
$durations = [int[]]$t.Tensors['Durations']
$totalTicks = $pitch.Length

Write-Host "Evidence Geometry: $totalTicks ticks, 512 channels ($($features.Length) total floats)"

# 2. Extract Subspace Mean (mu) and Leading Principal Axes (U)
Write-Host "`n--- Computing 512-Channel Acoustic Subspace (Rank $Rank) ---"
$timer = [Diagnostics.Stopwatch]::StartNew()

$mean = [double[]]::new(512)
for ($tick = 0; $tick -lt $totalTicks; $tick++) {
    $offset = $tick * 512
    for ($c = 0; $c -lt 512; $c++) {
        $mean[$c] += $features[$offset + $c]
    }
}
for ($c = 0; $c -lt 512; $c++) { $mean[$c] /= $totalTicks }

# Subspace iteration / Power iteration for top Rank axes
# Center the data matrix
$centered = [float[]]::new($features.Length)
for ($tick = 0; $tick -lt $totalTicks; $tick++) {
    $offset = $tick * 512
    for ($c = 0; $c -lt 512; $c++) {
        $centered[$offset + $c] = [float]($features[$offset + $c] - $mean[$c])
    }
}

# Simple Gram-Schmidt subspace extraction for the top Rank principal components
$axes = [float[][]]::new($Rank)
$rnd = [Random]::new(42)

for ($r = 0; $r -lt $Rank; $r++) {
    $v = [float[]]::new(512)
    for ($c = 0; $c -lt 512; $c++) { $v[$c] = [float]($rnd.NextDouble() - 0.5) }
    
    # 5 iterations of power method
    for ($iter = 0; $iter -lt 5; $iter++) {
        # v = X * (X^T * v)
        # 1. dot = X^T * v (over all ticks)
        $dots = [float[]]::new($totalTicks)
        for ($tick = 0; $tick -lt $totalTicks; $tick++) {
            $offset = $tick * 512
            $d = 0.0
            for ($c = 0; $c -lt 512; $c++) {
                $d += $centered[$offset + $c] * $v[$c]
            }
            $dots[$tick] = [float]$d
        }
        # 2. v_new = X * dots
        $vNew = [double[]]::new(512)
        for ($tick = 0; $tick -lt $totalTicks; $tick++) {
            $offset = $tick * 512
            $weight = $dots[$tick]
            for ($c = 0; $c -lt 512; $c++) {
                $vNew[$c] += $centered[$offset + $c] * $weight
            }
        }
        # Orthogonalize against previous axes
        for ($prev = 0; $prev -lt $r; $prev++) {
            $proj = 0.0
            for ($c = 0; $c -lt 512; $c++) { $proj += $vNew[$c] * $axes[$prev][$c] }
            for ($c = 0; $c -lt 512; $c++) { $vNew[$c] -= $proj * $axes[$prev][$c] }
        }
        # Normalize
        $norm = 0.0
        for ($c = 0; $c -lt 512; $c++) { $norm += $vNew[$c] * $vNew[$c] }
        $norm = [Math]::Sqrt($norm)
        if ($norm -gt 1e-9) {
            for ($c = 0; $c -lt 512; $c++) { $v[$c] = [float]($vNew[$c] / $norm) }
        }
    }
    $axes[$r] = $v
}
$subspaceMs = $timer.Elapsed.TotalMilliseconds
Write-Host "Subspace extracted in $([Math]::Round($subspaceMs, 2)) ms (Rank $Rank)"

# 3. Project Features onto Subspace Coordinates c(t), then Reconstruct x_procedural
Write-Host "`n--- Reconstructing Procedural Features x = mu + U * c ---"
$timer.Restart()
$proceduralFeatures = [float[]]::new($features.Length)

for ($tick = 0; $tick -lt $totalTicks; $tick++) {
    $offset = $tick * 512
    # c_r = dot(centered, axis_r)
    $coords = [float[]]::new($Rank)
    for ($r = 0; $r -lt $Rank; $r++) {
        $dot = 0.0
        for ($c = 0; $c -lt 512; $c++) {
            $dot += $centered[$offset + $c] * $axes[$r][$c]
        }
        $coords[$r] = [float]$dot
    }
    # x_rec = mu + sum(coords[r] * axis_r)
    for ($c = 0; $c -lt 512; $c++) {
        $val = $mean[$c]
        for ($r = 0; $r -lt $Rank; $r++) {
            $val += $coords[$r] * $axes[$r][$c]
        }
        $proceduralFeatures[$offset + $c] = [float]$val
    }
}
$reconstructMs = $timer.Elapsed.TotalMilliseconds

# Compute feature SNR
$sumSquareSignal = 0.0
$sumSquareNoise = 0.0
for ($i = 0; $i -lt $features.Length; $i++) {
    $diff = $features[$i] - $proceduralFeatures[$i]
    $sumSquareSignal += $features[$i] * $features[$i]
    $sumSquareNoise += $diff * $diff
}
$featureSnrDb = 10.0 * [Math]::Log10($sumSquareSignal / [Math]::Max(1e-12, $sumSquareNoise))
Write-Host "Procedural Reconstructed in $([Math]::Round($reconstructMs, 2)) ms"
Write-Host "512-Channel Feature Subspace SNR: $([Math]::Round($featureSnrDb, 2)) dB (Rank $Rank)"

# 4. Render through Generator Tail with Pinned VoiceBase AdaIN
Write-Host "`n--- Rendering Procedural x through Generator Tail (Pinned VoiceBase) ---"
$compiledDll = Join-Path $root 'build/experiment-first-slice/8692B55C19937F898A2F5F77527A573B2851BC89FD82A65A45D9F0C43128DC3A/Kokoro.OfflineRender.dll'
. (Join-Path $root 'tools/Invoke-KokoroPrecomputedDecoder.ps1') -Mode Library -OutputDirectory $out -CompiledAssembly $compiledDll -Threads 4

$voiceBasePath = Join-Path $root 'build/experiment-first-slice/af_heart_pinned_voicebase.clixml'
$rawVoiceBase = Import-Clixml -LiteralPath $voiceBasePath
$pinnedVoiceBase = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($k in $rawVoiceBase.Keys) { $pinnedVoiceBase.Add($k, $rawVoiceBase[$k]) }

$basePitchFloat = [float[]]$pitch

# Render 1: Baseline Neural Features
$timer.Restart()
$baselinePcm = Invoke-OfflineGenerator -Features $features -AcousticStyle $style -PitchCurve $basePitchFloat `
    -UniformDraw $rawUniform -HarmonicDraw $rawHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Supplied -SuppliedLevels $pinnedVoiceBase
$baseGenMs = $timer.Elapsed.TotalMilliseconds

# Render 2: Procedural Subspace Features (DECODER BYPASSED!)
$timer.Restart()
$proceduralPcm = Invoke-OfflineGenerator -Features $proceduralFeatures -AcousticStyle $style -PitchCurve $basePitchFloat `
    -UniformDraw $rawUniform -HarmonicDraw $rawHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Supplied -SuppliedLevels $pinnedVoiceBase
$procGenMs = $timer.Elapsed.TotalMilliseconds

# Save WAV files
function Save-PcmAsWav([float[]] $pcm, [string] $path) {
    $stream = [IO.File]::Create($path)
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $sampleRate = 24000
        $channels = 1
        $bitsPerSample = 16
        $byteRate = $sampleRate * $channels * ($bitsPerSample / 8)
        $blockAlign = $channels * ($bitsPerSample / 8)
        $dataBytes = $pcm.Length * 2

        $writer.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
        $writer.Write([int](36 + $dataBytes))
        $writer.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
        $writer.Write([int]16)
        $writer.Write([short]1)
        $writer.Write([short]$channels)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]$byteRate)
        $writer.Write([short]$blockAlign)
        $writer.Write([short]$bitsPerSample)
        $writer.Write([Text.Encoding]::ASCII.GetBytes("data"))
        $writer.Write([int]$dataBytes)

        for ($i = 0; $i -lt $pcm.Length; $i++) {
            $sample = [Math]::Clamp($pcm[$i], -1.0, 1.0)
            $shortVal = [short][Math]::Round($sample * 32767.0)
            $writer.Write($shortVal)
        }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$baseWav = Join-Path $out "baseline_neural.wav"
Save-PcmAsWav $baselinePcm $baseWav
$procWav = Join-Path $out "procedural_bypassed.wav"
Save-PcmAsWav $proceduralPcm $procWav

# 5. Measure Acoustic Audio Parity
$sampleCount = $baselinePcm.Length
$sumSig = 0.0
$sumDiff = 0.0
$sumSquareBase = 0.0
$sumSquareProc = 0.0

for ($i = 0; $i -lt $sampleCount; $i++) {
    $diff = $proceduralPcm[$i] - $baselinePcm[$i]
    $sumSig += $baselinePcm[$i] * $baselinePcm[$i]
    $sumDiff += $diff * $diff
    $sumSquareBase += $baselinePcm[$i] * $baselinePcm[$i]
    $sumSquareProc += $proceduralPcm[$i] * $proceduralPcm[$i]
}
$pcmSnrDb = 10.0 * [Math]::Log10($sumSig / [Math]::Max(1e-12, $sumDiff))
$rmsBase = [Math]::Sqrt($sumSquareBase / $sampleCount)
$rmsProc = [Math]::Sqrt($sumSquareProc / $sampleCount)
$lufsBase = if ($rmsBase -gt 1e-9) { 20.0 * [Math]::Log10($rmsBase) - 0.691 } else { -999.0 }
$lufsProc = if ($rmsProc -gt 1e-9) { 20.0 * [Math]::Log10($rmsProc) - 0.691 } else { -999.0 }

$telemetry = [ordered]@{
    Rank = $Rank
    TotalTicks = $totalTicks
    AudioSeconds = [Math]::Round($totalTicks / 80.0, 3)
    FeatureSnrDb = [Math]::Round($featureSnrDb, 2)
    PcmSnrDb = [Math]::Round($pcmSnrDb, 2)
    BaselineLufs = [Math]::Round($lufsBase, 2)
    ProceduralLufs = [Math]::Round($lufsProc, 2)
    LoudnessDeltaDb = [Math]::Round([Math]::Abs($lufsProc - $lufsBase), 3)
    BaselineGenMs = [Math]::Round($baseGenMs, 2)
    ProceduralGenMs = [Math]::Round($procGenMs, 2)
}

Write-Host "`n=== PROCEDURAL DECODER-BYPASS TELEMETRY ==="
$telemetry | Format-Table -AutoSize | Out-String | Write-Host

# 6. Play Procedural Bypassed Audio on Phone Speaker
if ($PlayOnPhone) {
    Write-Host "Staging procedural bypassed audio to OnePlus 11 via ADB..."
    & C:\dev\pwsh\scripts\adb.ps1 push $procWav /sdcard/procedural_bypassed.wav
    Write-Host "Triggering playback on phone speaker..."
    & C:\dev\pwsh\scripts\adb.ps1 shell 'am start -a android.intent.action.VIEW -d file:///sdcard/procedural_bypassed.wav -t audio/wav'
}

Export-Clixml -LiteralPath (Join-Path $out "telemetry.clixml") -InputObject ([pscustomobject]$telemetry)
Write-Host "Completed successfully."
