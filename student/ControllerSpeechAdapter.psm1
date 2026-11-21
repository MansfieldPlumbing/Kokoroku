#requires -Version 7.4
# Physical Controller Adapter for Kokoro Performance Score
# Maps controller stick/trigger/gyro axes and buttons into typed SpeechScoreEvents
# compatible with the 12-byte layout in Invoke-Student.ps1 and MIDI 2.0 UMP.

using module ./SpeechPerformanceScore.psm1

class ControllerSpeechState {
    [double] $PitchBendSemitones = 0.0  # Right Stick Y or Pitch Wheel (-48 to +48)
    [double] $AirflowEffort = 0.0       # Left Trigger / Bellows pressure (0.0 to 1.0)
    [double] $Aperiodicity = 0.0        # Right Trigger / Friction (0.0 to 1.0)
    [double] $TiltDb = 0.0              # Gyro Tilt (-96 to +96 dB/octave)
    [bool] $Voiced = $true
    [bool] $NoteActive = $false
}

class ControllerSpeechAdapter {
    [SpeechPerformanceScore] $Score
    [ControllerSpeechState] $CurrentState = [ControllerSpeechState]::new()
    [int] $CurrentTick = 0
    [int] $ActiveGestureStartTick = -1
    [SpeechGestureKind] $ActiveGestureKind = [SpeechGestureKind]::None

    ControllerSpeechAdapter([SpeechPerformanceScore] $score) {
        $this.Score = $score
    }

    [void] UpdateInput([int] $tick, [double] $pitchSemitones, [double] $bellowsAir, [bool] $isVoiced, [bool] $isNoteOn) {
        $this.CurrentTick = $tick
        $this.CurrentState.PitchBendSemitones = $pitchSemitones
        $this.CurrentState.AirflowEffort = $bellowsAir
        $this.CurrentState.Voiced = $isVoiced

        if ($isNoteOn -and -not $this.CurrentState.NoteActive) {
            # Note onset: begin active gesture
            $this.CurrentState.NoteActive = $true
            $this.ActiveGestureStartTick = $tick
            $this.ActiveGestureKind = if ($isVoiced) { [SpeechGestureKind]::PitchRise } else { [SpeechGestureKind]::Breath }
        } elseif (-not $isNoteOn -and $this.CurrentState.NoteActive) {
            # Note release: commit gesture event to score
            $this.CurrentState.NoteActive = $false
            $dur = [Math]::Max(1, $tick - $this.ActiveGestureStartTick)

            $ev = [SpeechScoreEvent]::new()
            $ev.Tick = $this.ActiveGestureStartTick
            $ev.DurationTicks = $dur
            $ev.Gesture = $this.ActiveGestureKind
            $ev.Role = if ($isVoiced) { [SpeechDeliveryRole]::Expressive } else { [SpeechDeliveryRole]::Hush }
            $ev.Magnitude = $pitchSemitones
            $this.Score.AddEvent($ev)

            $this.ActiveGestureStartTick = -1
            $this.ActiveGestureKind = [SpeechGestureKind]::None
        }
    }
}
