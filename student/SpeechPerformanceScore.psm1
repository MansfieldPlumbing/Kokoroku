#requires -Version 7.4
# Canonical Speech Performance Score and Gesture Types
# Follows NIST / PowerShell / CoreCLR conventions without ad hoc C# compilation.

enum SpeechGestureKind {
    None = 0
    PitchRise = 1
    PitchFall = 2
    PitchHold = 3
    Emphasis = 4
    Aperiodicity = 5
    Breath = 6
    Silence = 7
    BellowsSwell = 8   # Combined energy + harmonic noise modulation
    SpectralTilt = 9   # Formant balance / brightness tilt
}

enum SpeechDeliveryRole {
    Neutral = 0
    Expressive = 1
    Inquiry = 2
    Hum = 3
    Hush = 4
    Sigh = 5
}

class SpeechScoreEvent {
    [int] $Tick                  # Start tick on the 80 Hz generator clock
    [int] $DurationTicks         # Duration in 80 Hz ticks
    [SpeechGestureKind] $Gesture # The semantic intention
    [SpeechDeliveryRole] $Role   # Delivery role / communicative context
    [double] $Magnitude          # Parametric magnitude (e.g. semitones for pitch, dB for level, ratio for noise)
    [double] $RiseRatio          # Fraction of duration spent rising (0.0 - 1.0)
    [double] $ReleaseRatio       # Fraction of duration spent settling/releasing (0.0 - 1.0)
    [string] $ReferentOccurrence # Source text span or occurrence reference
    [string] $EvidenceNote       # Causal justification or provenance note
    [bool] $Committed            # Whether playback has committed this event

    SpeechScoreEvent() {
        $this.RiseRatio = 0.3
        $this.ReleaseRatio = 0.3
        $this.Committed = $false
    }
}

class SpeechPerformanceScore {
    [string] $Identity
    [string] $SourceHash
    [string] $Provenance
    [int] $Ticks
    [Collections.Generic.List[SpeechScoreEvent]] $Events = [Collections.Generic.List[SpeechScoreEvent]]::new()
    [int] $CommitBoundaryTick = 0

    [void] AddEvent([SpeechScoreEvent] $ev) {
        $this.Events.Add($ev)
    }

    [SpeechScoreEvent[]] GetActiveEventsAt([int] $tick) {
        $active = [Collections.Generic.List[SpeechScoreEvent]]::new()
        foreach ($e in $this.Events) {
            if ($tick -ge $e.Tick -and $tick -lt ($e.Tick + $e.DurationTicks)) {
                $active.Add($e)
            }
        }
        return $active.ToArray()
    }
}

class SpeechProjectionShim {
    # Project canonical score events onto a baseline F0 contour at 80 Hz
    static [single[]] ProjectF0([single[]] $baselineF0, [SpeechPerformanceScore] $score) {
        $f0 = [single[]]$baselineF0.Clone()
        $totalTicks = $f0.Length

        foreach ($e in $score.Events) {
            if ($e.Gesture -in [SpeechGestureKind]::PitchRise, [SpeechGestureKind]::PitchHold, [SpeechGestureKind]::PitchFall) {
                $start = $e.Tick
                $dur = $e.DurationTicks
                $end = [Math]::Min($totalTicks, $start + $dur)
                if ($start -ge $totalTicks -or $dur -le 0) { continue }

                $riseTicks = [Math]::Max(1, [int][Math]::Round($dur * $e.RiseRatio))
                $releaseTicks = [Math]::Max(1, [int][Math]::Round($dur * $e.ReleaseRatio))
                $holdTicks = [Math]::Max(0, $dur - $riseTicks - $releaseTicks)

                for ($t = $start; $t -lt $end; $t++) {
                    $base = $f0[$t]
                    if ($base -le 10.0) { continue }

                    $pos = $t - $start
                    $gain = 0.0
                    if ($pos -lt $riseTicks) {
                        $phase = [Math]::PI * ($pos / [double]$riseTicks)
                        $gain = 0.5 * (1.0 - [Math]::Cos($phase))
                    } elseif ($pos -lt ($riseTicks + $holdTicks)) {
                        $gain = 1.0
                    } else {
                        $relPos = $pos - ($riseTicks + $holdTicks)
                        $phase = [Math]::PI * ($relPos / [double]$releaseTicks)
                        $gain = 0.5 * (1.0 + [Math]::Cos($phase))
                    }

                    $semitones = $e.Magnitude * $gain
                    if ($e.Gesture -eq [SpeechGestureKind]::PitchFall) {
                        $semitones = -$semitones
                    }
                    $factor = [Math]::Pow(2.0, $semitones / 12.0)
                    $f0[$t] = [single]($base * $factor)
                }
            }
        }
        return $f0
    }

    # Project breath/swell gestures onto harmonic noise draws (2,700 samples per 80 Hz tick = 9 harmonics x 300 samples)
    static [float[]] ProjectHarmonicNoise([float[]] $baselineHarmonic, [single[]] $f0, [SpeechPerformanceScore] $score) {
        $harmonic = [float[]]$baselineHarmonic.Clone()
        $totalTicks = $f0.Length

        foreach ($e in $score.Events) {
            if ($e.Gesture -in [SpeechGestureKind]::Breath, [SpeechGestureKind]::BellowsSwell) {
                $start = $e.Tick
                $dur = $e.DurationTicks
                $end = [Math]::Min($totalTicks, $start + $dur)
                if ($start -ge $totalTicks -or $dur -le 0) { continue }

                $riseTicks = [Math]::Max(1, [int][Math]::Round($dur * $e.RiseRatio))
                $releaseTicks = [Math]::Max(1, [int][Math]::Round($dur * $e.ReleaseRatio))
                $holdTicks = [Math]::Max(0, $dur - $riseTicks - $releaseTicks)

                for ($t = $start; $t -lt $end; $t++) {
                    $pos = $t - $start
                    $gain = 0.0
                    if ($pos -lt $riseTicks) {
                        $phase = [Math]::PI * ($pos / [double]$riseTicks)
                        $gain = 0.5 * (1.0 - [Math]::Cos($phase))
                    } elseif ($pos -lt ($riseTicks + $holdTicks)) {
                        $gain = 1.0
                    } else {
                        $relPos = $pos - ($riseTicks + $holdTicks)
                        $phase = [Math]::PI * ($relPos / [double]$releaseTicks)
                        $gain = 0.5 * (1.0 + [Math]::Cos($phase))
                    }

                    # Scale harmonic noise draw in this tick
                    # Magnitude: 0.0 = completely quiet/dry, 1.0 = baseline, 2.0+ = breathy swell
                    $scale = 1.0 + ($e.Magnitude - 1.0) * $gain
                    $offset = $t * 2700
                    for ($i = $offset; $i -lt $offset + 2700; $i++) {
                        $harmonic[$i] = [float]($harmonic[$i] * $scale)
                    }
                }
            }
        }
        return $harmonic
    }
}
