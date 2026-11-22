#requires -Version 7.4
# Rank every retained Kokoro paired-teacher WAV against a generator tick length.
# Uses the source-bank's native StudentTeacherObservation/1 index and verifies WAV headers.
# No teacher, front end, decoder, or generator execution is needed.
[CmdletBinding()]
param(
    [string] $BankPath = (Join-Path (Get-Location).Path 'data/source-bank'),
    [ValidateRange(1, 10000000)][int] $TargetTicks = 942,
    [ValidateRange(0, 100000)][int] $Top = 0,
    [switch] $PassThru,
    [string] $TextContains
)
$ErrorActionPreference = 'Stop'

class PairedTeacherTickComparison {
    [string] $Id
    [string] $SourceId
    [int] $SentenceIndex
    [string] $Text
    [long] $Samples
    [double] $GeneratorTicks
    [double] $Seconds
    [long] $SampleDelta
    [double] $TickDelta
    [bool] $ExactSampleMatch
    [bool] $WholeGeneratorTicks
    [bool] $HasStockExecution
    [bool] $HasProceduralExecution
    [string] $Directory
}

function Read-WaveSamples {
    param([Parameter(Mandatory)][string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 44) { throw "Truncated WAV: $Path" }
        $ascii = [Text.Encoding]::ASCII
        $riff = $ascii.GetString($reader.ReadBytes(4))
        $null = $reader.ReadUInt32()
        $wave = $ascii.GetString($reader.ReadBytes(4))
        if ($riff -cne 'RIFF' -or $wave -cne 'WAVE') { throw "Not RIFF WAVE: $Path" }
        $format = -1
        $channels = -1
        $sampleRate = -1
        $blockAlign = -1
        $bitsPerSample = -1
        $dataBytes = -1L
        while ($stream.Position + 8 -le $stream.Length) {
            $id = $ascii.GetString($reader.ReadBytes(4))
            $chunkLength = [long]$reader.ReadUInt32()
            $chunkStart = $stream.Position
            if ($chunkLength -gt $stream.Length - $chunkStart) { throw "Truncated WAV chunk '$id': $Path" }
            if ($id -ceq 'fmt ') {
                if ($chunkLength -lt 16) { throw "Invalid fmt chunk: $Path" }
                $format = [int]$reader.ReadUInt16()
                $channels = [int]$reader.ReadUInt16()
                $sampleRate = [int]$reader.ReadUInt32()
                $null = $reader.ReadUInt32() # byte rate
                $blockAlign = [int]$reader.ReadUInt16()
                $bitsPerSample = [int]$reader.ReadUInt16()
            } elseif ($id -ceq 'data') {
                if ($dataBytes -ge 0) { throw "Multiple data chunks: $Path" }
                $dataBytes = $chunkLength
            }
            $next = $chunkStart + $chunkLength + ($chunkLength % 2)
            if ($next -gt $stream.Length) { throw "Malformed WAV padding: $Path" }
            $stream.Position = $next
        }
        if ($format -ne 1 -or $channels -ne 1 -or $sampleRate -ne 24000 -or
            $bitsPerSample -ne 16 -or $blockAlign -ne 2 -or $dataBytes -lt 0 -or ($dataBytes % 2)) {
            throw "Unexpected WAV format (must be PCM16, mono, 24000 Hz): $Path"
        }
        return [long]($dataBytes / $blockAlign)
    } finally { $reader.Dispose() }
}

$bank = (Resolve-Path -LiteralPath $BankPath).Path
$teacherRoot = Join-Path $bank 'paired-teachers'
if (!(Test-Path -LiteralPath $teacherRoot -PathType Container)) { throw "Missing teacher bank: $teacherRoot" }
$targetSamples = [long]$TargetTicks * 300L # 24,000 audio samples/s divided by 80 generator ticks/s
$directories = @(Get-ChildItem -LiteralPath $teacherRoot -Directory |
    Where-Object Name -NotLike '*.partial' | Sort-Object Name)
$records = [Collections.Generic.List[PairedTeacherTickComparison]]::new()
foreach ($directory in $directories) {
    $observation = Join-Path $directory.FullName 'observation.bin'
    $wavePath = Join-Path $directory.FullName 'kokoro.wav'
    if (!(Test-Path -LiteralPath $observation -PathType Leaf)) { throw "Missing observation.bin: $($directory.FullName)" }
    if (!(Test-Path -LiteralPath $wavePath -PathType Leaf)) { throw "Missing kokoro.wav: $($directory.FullName)" }
    $r = [IO.BinaryReader]::new([IO.File]::OpenRead($observation))
    try {
        if ($r.ReadString() -cne 'StudentTeacherObservation/1') {
            throw "Unexpected observation format: $observation"
        }
        $sourceId = $r.ReadString()
        $null = $r.ReadString() # configuration
        $null = $r.ReadInt32()  # original source offset
        $null = $r.ReadInt32()  # source length
        $text = $r.ReadString()
        $null = $r.ReadString() # phones
        $observationSamples = $r.ReadInt64()
        $sentenceIndex = $r.ReadInt32()
    } finally { $r.Dispose() }
    $samples = Read-WaveSamples $wavePath
    if ($samples -ne $observationSamples) {
        throw "Metadata/WAV count mismatch: $($directory.Name): observation=$observationSamples WAV=$samples"
    }
    $entry = [PairedTeacherTickComparison]::new()
    $entry.Id = $directory.Name
    $entry.SourceId = $sourceId
    $entry.SentenceIndex = $sentenceIndex
    $entry.Text = $text
    $entry.Samples = $samples
    $entry.Seconds = $samples / 24000.0
    $entry.GeneratorTicks = $samples / 300.0
    $entry.SampleDelta = $samples - $targetSamples
    $entry.TickDelta = $entry.GeneratorTicks - $TargetTicks
    $entry.ExactSampleMatch = ($samples -eq $targetSamples)
    $entry.WholeGeneratorTicks = (($samples % 300L) -eq 0L)
    $entry.HasStockExecution = Test-Path -LiteralPath (Join-Path $directory.FullName 'stock-execution.bin') -PathType Leaf
    $entry.HasProceduralExecution = Test-Path -LiteralPath (Join-Path $directory.FullName 'procedural-execution.bin') -PathType Leaf
    $entry.Directory = $directory.FullName
    $records.Add($entry)
}

$matching = if ($TextContains) { @($records | Where-Object { $_.Text.Contains($TextContains, [StringComparison]::OrdinalIgnoreCase) }) } else { @($records) }
$ordered = @($matching | Sort-Object @{Expression = { [Math]::Abs($_.SampleDelta) }}, @{Expression = 'Id'})
Write-Host "Directories=$($directories.Count) Verified=$($records.Count) TargetTicks=$TargetTicks TargetSamples=$targetSamples"
Write-Host "ExactSampleMatches=$(($records | Where-Object ExactSampleMatch).Count) NonIntegralTickRecords=$(($records | Where-Object { !$_.WholeGeneratorTicks }).Count) FilteredRecords=$($matching.Count)"
Write-Host "Nearest records (SampleDelta is signed; 1 generator tick = 300 PCM samples):"
$view = if ($Top -gt 0) { @($ordered | Select-Object -First $Top) } else { $ordered }
if ($PassThru) { $view; return }
$view | Select-Object @{Name='Id';Expression={$_.Id.Substring(0,[Math]::Min(8,$_.Id.Length))}}, SourceId, Samples, GeneratorTicks, TickDelta, ExactSampleMatch |
    Format-Table -AutoSize | Out-Host
# Use -PassThru to return the typed objects without console-table formatting.
