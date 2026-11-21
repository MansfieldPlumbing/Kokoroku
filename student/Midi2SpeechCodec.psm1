#requires -Version 7.7
# MIDI 2.0 Universal MIDI Packet (UMP) Codec for Speech Performance Scores
# Implements 32-bit and 64-bit UMP packet serialization/deserialization.
# Uses MIDI 2.0 Channel Voice (CV) message type 0x4 (64-bit UMP) for standard note/pitch-bend,
# and Flex Data (type 0xD) / SysEx8 (type 0x5) conventions for project-defined speech semantics.

using module ./SpeechPerformanceScore.psm1

class Midi2SpeechCodec {
    hidden static [uint32] ToU32([long] $val) {
        $bytes = [BitConverter]::GetBytes($val)
        return [BitConverter]::ToUInt32($bytes, 0)
    }

    static [uint32[]] EncodeScoreToUmp([SpeechPerformanceScore] $score) {
        $packets = [Collections.Generic.List[uint32]]::new()
        
        # Header / Meta Packet: Type 0xD (Flex Data), Group 0, Status 0x01 (Metadata)
        $headerWord0 = [Midi2SpeechCodec]::ToU32(0xD0010000L)
        $headerWord1 = [Midi2SpeechCodec]::ToU32([long]$score.Ticks)
        $packets.Add($headerWord0)
        $packets.Add($headerWord1)

        foreach ($e in $score.Events) {
            $group = 0L
            $channel = 0L
            
            # Status 0xE = Pitch Bend (32-bit resolution: 0x80000000 = center)
            $bendCenter = 0x80000000L
            $semitoneStep = [double]0x80000000L / 48.0
            $offset = [long]($e.Magnitude * $semitoneStep)
            $rawBend = [Math]::Clamp($bendCenter + $offset, 0L, 0xFFFFFFFFL)
            $bendWord1 = [Midi2SpeechCodec]::ToU32($rawBend)

            # Word 0: [Type: 4 = 0x4, Group: 4 = 0, Status: 4 = 0xE, Channel: 4 = 0, Tick: 16 bits]
            $w0Val = (4L -shl 28) -bor ($group -shl 24) -bor (0xEL -shl 20) -bor ($channel -shl 16) -bor ([long]$e.Tick -band 0xFFFFL)
            $word0 = [Midi2SpeechCodec]::ToU32($w0Val)
            $packets.Add($word0)
            $packets.Add($bendWord1)

            # Note On / Duration packet
            $note = [long][int]$e.Gesture
            $role = [long][int]$e.Role
            $vel = [long]$e.DurationTicks
            $nW0Val = (4L -shl 28) -bor ($group -shl 24) -bor (0x9L -shl 20) -bor ($channel -shl 16) -bor ($note -shl 8) -bor $role
            $noteWord0 = [Midi2SpeechCodec]::ToU32($nW0Val)
            $packets.Add($noteWord0)
            $packets.Add([Midi2SpeechCodec]::ToU32($vel))
        }

        return $packets.ToArray()
    }

    static [SpeechPerformanceScore] DecodeUmpToScore([uint32[]] $packets, [string] $identity) {
        $score = [SpeechPerformanceScore]::new()
        $score.Identity = $identity
        
        if ($packets.Length -lt 2) { return $score }
        $idx = 0
        
        # Check header
        $h0 = [long]$packets[0]
        if (($h0 -band 0xF0000000L) -eq 0xD0000000L) {
            $score.Ticks = [int]$packets[1]
            $idx = 2
        }

        while ($idx + 3 -lt $packets.Length) {
            $w0 = [long]$packets[$idx]
            $w1 = [long]$packets[$idx + 1]
            $w2 = [long]$packets[$idx + 2]
            $w3 = [long]$packets[$idx + 3]

            $type = ($w0 -shr 28) -band 0xFL
            $status = ($w0 -shr 20) -band 0xFL

            if ($type -eq 4L -and $status -eq 0xEL) {
                $tick = [int]($w0 -band 0xFFFFL)
                $bendVal = $w1
                $bendCenter = 0x80000000L
                $semitoneStep = [double]0x80000000L / 48.0
                $mag = ($bendVal - $bendCenter) / $semitoneStep

                $nType = ($w2 -shr 28) -band 0xFL
                $nStatus = ($w2 -shr 20) -band 0xFL
                if ($nType -eq 4L -and $nStatus -eq 9L) {
                    $gesture = [SpeechGestureKind](($w2 -shr 8) -band 0xFFL)
                    $role = [SpeechDeliveryRole]($w2 -band 0xFFL)
                    $dur = [int]$w3

                    $e = [SpeechScoreEvent]::new()
                    $e.Tick = $tick
                    $e.DurationTicks = $dur
                    $e.Gesture = $gesture
                    $e.Role = $role
                    $e.Magnitude = [Math]::Round($mag, 3)
                    $score.AddEvent($e)
                }
                $idx += 4
            } else {
                $idx += 2
            }
        }
        return $score
    }
}
