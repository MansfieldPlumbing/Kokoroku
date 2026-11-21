#requires -Version 7.4
# Test-AliceLiveParagraph.ps1
# End-to-end synthesis of the full Alice paragraph:
# Text -> Compiled English Phonemizer -> DSP Decoder (512-ch features + F0)
# -> Procedural Performance Score Injection -> Generator (Pinned VoiceBase AdaIN)
# -> Raw Telemetry & Timing Cycles -> Direct Playback on OnePlus 11 Speaker.

using module ../student/SpeechPerformanceScore.psm1
using module ../student/Midi2SpeechCodec.psm1

param(
    [string] $Voice = 'af_heart',
    [string] $OutputDir = 'build/alice-live-paragraph',
    [switch] $PlayOnPhone
)

$ErrorActionPreference = 'Stop'
$root = 'C:\dev\kokoro-hexagon'
$out = [IO.Path]::GetFullPath((Join-Path $root $OutputDir))
$null = [IO.Directory]::CreateDirectory($out)

Write-Host "=========================================================="
Write-Host "   ALICE IN WONDERLAND FULL PARAGRAPH: LIVE END-TO-END    "
Write-Host "=========================================================="

# 1. Text to Synthesize
$fullText = "The Queen had only one way of settling all difficulties, great or small: `"Off with her head!`" she said, without even looking round."
Write-Host "`nSource Text:`n  `"$fullText`""

# 2. Compile/Load English Phonemizer
$timer = [Diagnostics.Stopwatch]::StartNew()
$driverDir = Join-Path $root 'build/phonemizer/english/driver/5DF96F16D24C38A03AFFE6E0DA9AD69062D51D6E930A3FFA044C97BBCF1261AE-library-dll'
$driverDll = Join-Path $driverDir 'Dev.MansfieldPlumbing.English.Driver.5DF96F16D24C38A0.dll'
$assembly = [Reflection.Assembly]::LoadFrom($driverDll)
$coreDriverRun = $assembly.GetType('CoreDriver', $true).GetMethod('Run').CreateDelegate([Func[string,object]])

$pronunciation = $coreDriverRun.Invoke($fullText)
if (-not $pronunciation.Complete -or -not $pronunciation.KokoroPhones) {
    throw "Phonemizer failed to resolve text."
}
$phonemes = [string]$pronunciation.KokoroPhones
$phonemizeMs = $timer.Elapsed.TotalMilliseconds
Write-Host "`nPhonemes ($([Math]::Round($phonemizeMs, 2)) ms):`n  $phonemes"

# 3. Initialize Offline Speech Library
$timer.Restart()
$compiledDll = Join-Path $root 'build/experiment-first-slice/8692B55C19937F898A2F5F77527A573B2851BC89FD82A65A45D9F0C43128DC3A/Kokoro.OfflineRender.dll'
. (Join-Path $root 'tools/Invoke-KokoroPrecomputedDecoder.ps1') -Mode Library -OutputDirectory $out -CompiledAssembly $compiledDll -Threads 4
$libInitMs = $timer.Elapsed.TotalMilliseconds

# 4. Load Pinned 48-site VoiceBase
$voiceBasePath = Join-Path $root 'build/experiment-first-slice/af_heart_pinned_voicebase.clixml'
$rawVoiceBase = Import-Clixml -LiteralPath $voiceBasePath
$pinnedVoiceBase = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($k in $rawVoiceBase.Keys) {
    $pinnedVoiceBase.Add($k, $rawVoiceBase[$k])
}
Write-Host "Loaded Pinned VoiceBase: $($pinnedVoiceBase.Count) sites"

# 5. Run Frontend Predictor + Decoder to generate 512-channel x and F0
Write-Host "`n--- Running Text Encoder + Predictor + Decoder ---"
$timer.Restart()
$decoded = Invoke-OfflineSpeech -Phonemes $phonemes -Voice $Voice -SkipGenerator
$decodeMs = $timer.Elapsed.TotalMilliseconds

$features = [float[]]$decoded.Features
$f0 = [float[]]$decoded.F0
$durations = [int[]]$decoded.Durations
$style = [float[]]$decoded.AcousticStyle
$totalTicks = $f0.Length
$audioSeconds = $totalTicks / 80.0
$totalSamples = $totalTicks * 300

Write-Host "Decoded Geometry: $totalTicks ticks ($([Math]::Round($audioSeconds, 3)) s audio, $totalSamples samples, 512 channels)"
Write-Host "Decoder Execution Time: $([Math]::Round($decodeMs, 2)) ms (Decoder RTF: $([Math]::Round($decodeMs / ($audioSeconds * 1000.0), 3))x)"

# 6. Generate Deterministic Excitation Draws
$draws = New-OfflineDraws $totalSamples
$rawUniform = $draws.Uniform
$rawHarmonic = $draws.Harmonic
$rawExtra = $draws.Extra

# Helper to save 16-bit PCM WAV
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

# 7. Render Baseline under Pinned VoiceBase
Write-Host "`n--- Rendering Baseline Generator under Pinned VoiceBase ---"
$timer.Restart()
$basePcm = Invoke-OfflineGenerator -Features $features -AcousticStyle $style -PitchCurve $f0 `
    -UniformDraw $rawUniform -HarmonicDraw $rawHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Supplied -SuppliedLevels $pinnedVoiceBase
$baseGenMs = $timer.Elapsed.TotalMilliseconds
Write-Host "Generator Baseline Execution Time: $([Math]::Round($baseGenMs, 2)) ms (Host RTF: $([Math]::Round($baseGenMs / ($audioSeconds * 1000.0), 3))x)"

$baseWav = Join-Path $out "alice_baseline.wav"
Save-PcmAsWav $basePcm $baseWav
$baseHash = (Get-FileHash -LiteralPath $baseWav).Hash

# 8. Procedural Performance Score Modulation
Write-Host "`n--- Applying Procedural Performance Score ---"
$score = [SpeechPerformanceScore]::new()
$score.Identity = "Alice_Live_Paragraph_Performance"
$score.Ticks = $totalTicks

# Gesture A: Dramatic Pitch Rise on "'Off with her head!'"
$headEvent = [SpeechScoreEvent]::new()
$headEvent.Tick = [int][Math]::Round($totalTicks * 0.58)
$headEvent.DurationTicks = [int][Math]::Round($totalTicks * 0.12)
$headEvent.Gesture = [SpeechGestureKind]::PitchRise
$headEvent.Role = [SpeechDeliveryRole]::Expressive
$headEvent.Magnitude = 4.5    # +4.5 semitones imperious rise!
$headEvent.RiseRatio = 0.25
$headEvent.ReleaseRatio = 0.35
$headEvent.ReferentOccurrence = "Off with her head!"
$headEvent.EvidenceNote = "Imperious command intonation"
$score.AddEvent($headEvent)

# Gesture B: Breathy release into the silence on "...looking round."
$breathEvent = [SpeechScoreEvent]::new()
$breathEvent.Tick = [int][Math]::Round($totalTicks * 0.88)
$breathEvent.DurationTicks = [int][Math]::Round($totalTicks * 0.10)
$breathEvent.Gesture = [SpeechGestureKind]::BellowsSwell
$breathEvent.Role = [SpeechDeliveryRole]::Sigh
$breathEvent.Magnitude = 2.0  # 2.0x airflow swell
$breathEvent.RiseRatio = 0.3
$breathEvent.ReleaseRatio = 0.4
$breathEvent.ReferentOccurrence = "looking round."
$breathEvent.EvidenceNote = "Sigh / dismissal vocalic breath"
$score.AddEvent($breathEvent)

$f0Single = [single[]]$f0
$perfPitch = [float[]]([SpeechProjectionShim]::ProjectF0($f0Single, $score))
$perfHarmonic = [SpeechProjectionShim]::ProjectHarmonicNoise($rawHarmonic, $f0Single, $score)

# 9. Render Performed Generator under Pinned VoiceBase
Write-Host "`n--- Rendering Performed Generator under Pinned VoiceBase ---"
$timer.Restart()
$perfPcm = Invoke-OfflineGenerator -Features $features -AcousticStyle $style -PitchCurve $perfPitch `
    -UniformDraw $rawUniform -HarmonicDraw $perfHarmonic -ExtraDraw $rawExtra `
    -TokenDurations $durations -LevelMode Supplied -SuppliedLevels $pinnedVoiceBase
$perfGenMs = $timer.Elapsed.TotalMilliseconds
Write-Host "Generator Performed Execution Time: $([Math]::Round($perfGenMs, 2)) ms"

$perfWav = Join-Path $out "alice_performed.wav"
Save-PcmAsWav $perfPcm $perfWav
$perfHash = (Get-FileHash -LiteralPath $perfWav).Hash

# 10. Measure Ground-Truth Telemetry
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
    AudioSeconds = [Math]::Round($audioSeconds, 3)
    TotalSamples = $sampleCount
    PhonemizerMs = [Math]::Round($phonemizeMs, 2)
    DecoderMs = [Math]::Round($decodeMs, 2)
    HostGeneratorMs = [Math]::Round($perfGenMs, 2)
    ProjectedDspMs = [Math]::Round(($audioSeconds * 1000.0) / 128.16, 2)
    ChangedSamples = $deltaCount
    ChangedPercent = [Math]::Round(100.0 * $deltaCount / $sampleCount, 2)
    PeakSampleDelta = [Math]::Round($maxDelta, 6)
    DifferenceRmsDbFs = [Math]::Round($diffDbFs, 2)
    BaselineLufs = [Math]::Round($lufsA, 2)
    PerformedLufs = [Math]::Round($lufsB, 2)
    BaselineSHA256 = $baseHash
    PerformedSHA256 = $perfHash
}

Write-Host "`n=== PHYSICAL GROUND TRUTH & TIMING TELEMETRY ==="
$telemetry | Format-Table -AutoSize | Out-String | Write-Host

# 11. Push and Play on Phone Speaker
if ($PlayOnPhone) {
    Write-Host "`nStaging both WAVs to OnePlus 11 via ADB..."
    & C:\dev\pwsh\scripts\adb.ps1 push $baseWav /sdcard/alice_baseline.wav
    & C:\dev\pwsh\scripts\adb.ps1 push $perfWav /sdcard/alice_performed.wav
    Write-Host "Triggering performed audio on phone speaker..."
    & C:\dev\pwsh\scripts\adb.ps1 shell 'am start -a android.intent.action.VIEW -d file:///sdcard/alice_performed.wav -t audio/wav'
}

Export-Clixml -LiteralPath (Join-Path $out "telemetry.clixml") -InputObject ([pscustomobject]$telemetry)
Write-Host "Completed."
