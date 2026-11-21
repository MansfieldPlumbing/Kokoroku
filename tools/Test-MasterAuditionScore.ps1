#requires -Version 7.4
# Test-MasterAuditionScore.ps1
# Renders the Master Audition performance score under Baseline vs. Performed Score
# with Pinned VoiceBase AdaIN, measuring raw physical telemetry and playing on OnePlus 11.

using module ../student/SpeechPerformanceScore.psm1
using module ../student/Midi2SpeechCodec.psm1

param(
    [string] $Voice = 'af_heart',
    [string] $OutputDir = 'build/master-audition-score',
    [switch] $PlayOnPhone
)

$ErrorActionPreference = 'Stop'
$root = 'C:\dev\kokoro-hexagon'
$bank = Join-Path $root 'data/source-bank'

Write-Host "=== Master Audition Score Render ==="
$out = [IO.Path]::GetFullPath((Join-Path $root $OutputDir))
$null = [IO.Directory]::CreateDirectory($out)

# 1. Initialize Offline Library
Write-Host "--- Initializing Offline Generator Library ---"
$compiledDll = Join-Path $root 'build/experiment-first-slice/8692B55C19937F898A2F5F77527A573B2851BC89FD82A65A45D9F0C43128DC3A/Kokoro.OfflineRender.dll'
. (Join-Path $root 'tools/Invoke-KokoroPrecomputedDecoder.ps1') -Mode Library -OutputDirectory $out -CompiledAssembly $compiledDll -Threads 4

# 2. Load Verified Observation Handoff
Write-Host "--- Loading Observation Handoff ---"
$field = & (Join-Path $root 'student/Open-StudentSpeechInvestigation.ps1') -BankPath $bank -SourceIdentity 'Gutenberg/11'
$t = $field.Comparisons[0].Teacher
$handoff = $t.StockExecution.DecoderHandoff

$features = [float[]]$handoff.GeneratorFeatures.Read()
$pitch = [single[]]$handoff.GeneratorPitch.Read()
$style = [float[]]$handoff.AcousticStyle.Read()
$rawUniform = [float[]]$handoff.UniformDraw.Read()
$rawHarmonic = [float[]]$handoff.HarmonicDraw.Read()
$rawExtra = [float[]]$handoff.ExtraDraw.Read()
$durations = [int[]]$t.Tensors['Durations']
$totalTicks = $pitch.Length

Write-Host "Stream Geometry: $totalTicks ticks, $($totalTicks * 300) samples ($([Math]::Round($totalTicks / 80.0, 3))s)"

# 3. Extract and Pin Reference VoiceBase AdaIN Table (48 sites)
Write-Host "--- Extracting Reference VoiceBase AdaIN Table ---"
$basePitchFloat = [float[]]$pitch
$liveExported = [Collections.Generic.List[OfflineLevelRecord]]::new()
$refPcm = Invoke-OfflineGenerator -Features $features -AcousticStyle $style -PitchCurve $basePitchFloat `
    -UniformDraw $rawUniform -HarmonicDraw $rawHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Live -LevelRecords $liveExported

$pinnedVoiceBase = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($rec in $liveExported) {
    $pinnedVoiceBase.Add($rec.Name, $rec)
}
Write-Host "Extracted active VoiceBase Table: $($pinnedVoiceBase.Count) sites registered"

# Helper function to save 24 kHz 16-bit PCM WAV
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
        $writer.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
        $writer.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
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

# 4. Render Baseline Score under Pinned VoiceBase
Write-Host "Rendering Baseline under Pinned VoiceBase..."
$basePitchFloat = [float[]]$pitch
$basePcm = Invoke-OfflineGenerator -Features $features -AcousticStyle $style -PitchCurve $basePitchFloat `
    -UniformDraw $rawUniform -HarmonicDraw $rawHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Supplied -SuppliedLevels $pinnedVoiceBase

$baseWav = Join-Path $out "audition_baseline.wav"
Save-PcmAsWav $basePcm $baseWav
$baseHash = (Get-FileHash -LiteralPath $baseWav).Hash
Write-Host "Baseline WAV SHA-256: $baseHash"

# 5. Formulate Master Audition Performance Score
Write-Host "Formulating Performance Score..."
$score = [SpeechPerformanceScore]::new()
$score.Identity = "MasterAudition_Climax_Hum"
$score.Ticks = $totalTicks

# Gesture 1: Pitch Rise (+4 semitones) over ticks 279..303
$riseEvent = [SpeechScoreEvent]::new()
$riseEvent.Tick = 279
$riseEvent.DurationTicks = 25
$riseEvent.Gesture = [SpeechGestureKind]::PitchRise
$riseEvent.Role = [SpeechDeliveryRole]::Expressive
$riseEvent.Magnitude = 4.0
$riseEvent.RiseRatio = 0.35
$riseEvent.ReleaseRatio = 0.35
$riseEvent.ReferentOccurrence = "low... zoo"
$riseEvent.EvidenceNote = "Expressive vocal pitch contour rise"
$score.AddEvent($riseEvent)

# Gesture 2: Bellows Swell (2.2x harmonic noise) over ticks 320..355
$swellEvent = [SpeechScoreEvent]::new()
$swellEvent.Tick = 320
$swellEvent.DurationTicks = 35
$swellEvent.Gesture = [SpeechGestureKind]::BellowsSwell
$swellEvent.Role = [SpeechDeliveryRole]::Hum
$swellEvent.Magnitude = 2.2
$swellEvent.RiseRatio = 0.3
$swellEvent.ReleaseRatio = 0.3
$swellEvent.ReferentOccurrence = "hum"
$swellEvent.EvidenceNote = "Breathy airflow release into tail"
$score.AddEvent($swellEvent)

# 6. Project Score Controls
$performedPitch = [SpeechProjectionShim]::ProjectF0($pitch, $score)
$performedPitchFloat = [float[]]$performedPitch

$performedHarmonic = [SpeechProjectionShim]::ProjectHarmonicNoise($rawHarmonic, $pitch, $score)

# 7. Render Performed Score under Pinned VoiceBase
Write-Host "Rendering Performed Score under Pinned VoiceBase..."
$perfPcm = Invoke-OfflineGenerator -Features $features -AcousticStyle $style -PitchCurve $performedPitchFloat `
    -UniformDraw $rawUniform -HarmonicDraw $performedHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Supplied -SuppliedLevels $pinnedVoiceBase

$perfWav = Join-Path $out "audition_performed.wav"
Save-PcmAsWav $perfPcm $perfWav
$perfHash = (Get-FileHash -LiteralPath $perfWav).Hash
Write-Host "Performed WAV SHA-256: $perfHash"

# 8. Compute Ground-Truth Physical Telemetry
$sampleCount = $basePcm.Length
$deltaCount = 0
$maxDelta = 0.0
$sumSquareDiff = 0.0
$sumSquareA = 0.0
$sumSquareB = 0.0

for ($i = 0; $i -lt $sampleCount; $i++) {
    $diff = [Math]::Abs($perfPcm[$i] - $basePcm[$i])
    if ($diff -gt 1e-7) { $deltaCount++ }
    if ($diff -gt $maxDelta) { $maxDelta = $diff }
    $sumSquareDiff += $diff * $diff
    $sumSquareA += $basePcm[$i] * $basePcm[$i]
    $sumSquareB += $perfPcm[$i] * $perfPcm[$i]
}

$rmsDiff = [Math]::Sqrt($sumSquareDiff / $sampleCount)
$diffDbFs = if ($rmsDiff -gt 1e-9) { 20.0 * [Math]::Log10($rmsDiff) } else { -999.0 }
$rmsA = [Math]::Sqrt($sumSquareA / $sampleCount)
$rmsB = [Math]::Sqrt($sumSquareB / $sampleCount)
$lufsA = if ($rmsA -gt 1e-9) { 20.0 * [Math]::Log10($rmsA) - 0.691 } else { -999.0 }
$lufsB = if ($rmsB -gt 1e-9) { 20.0 * [Math]::Log10($rmsB) - 0.691 } else { -999.0 }

$telemetry = [ordered]@{
    TotalSamples = $sampleCount
    DurationSeconds = [Math]::Round($sampleCount / 24000.0, 3)
    ChangedSamples = $deltaCount
    ChangedPercent = [Math]::Round(100.0 * $deltaCount / $sampleCount, 2)
    PeakSampleDelta = [Math]::Round($maxDelta, 6)
    DifferenceRmsDbFs = [Math]::Round($diffDbFs, 2)
    BaselineLufs = [Math]::Round($lufsA, 2)
    PerformedLufs = [Math]::Round($lufsB, 2)
}

Write-Host "`n=== PHYSICAL GROUND TRUTH TELEMETRY ==="
$telemetry | Format-Table -AutoSize | Out-String | Write-Host

# 9. Physical Phone Playback
if ($PlayOnPhone) {
    Write-Host "Staging audio to OnePlus 11 via ADB..."
    & C:\dev\pwsh\scripts\adb.ps1 push $perfWav /sdcard/audition_performed.wav
    Write-Host "Triggering phone playback on speaker..."
    & C:\dev\pwsh\scripts\adb.ps1 shell 'am start -a android.intent.action.VIEW -d file:///sdcard/audition_performed.wav -t audio/wav'
}

Export-Clixml -LiteralPath (Join-Path $out "telemetry.clixml") -InputObject ([pscustomobject]$telemetry)
Write-Host "Completed successfully."
