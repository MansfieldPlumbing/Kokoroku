# Paired-teacher utterance audit, 22 November 2026

This pass audited the retained paired-teachers source bank with particular attention to teacher utterance `032B5B23`, generator tick length relationships, the `AE6FD9EE` Kokoro audio, and the complete 60-record source-bank scan.

## Clock and generator tick conversion

The Kokoro generator in this repository operates on an 80 Hz frame clock (80 ticks per second) against a 24,000 Hz audio sample rate. The relationship between generator ticks and PCM audio samples is exact:

$$\text{Samples} = \text{Ticks} \times \frac{24000\text{ samples/sec}}{80\text{ ticks/sec}} = \text{Ticks} \times 300\text{ samples/tick}$$

- **942 generator ticks** = $942 \times 300 = 282,600$ audio samples (11.775 seconds at 24 kHz).
- This exactly matches the reference fixture `tools/fixtures/lighthouse-af_heart-float.wav` (282,600 samples, float32, 24 kHz mono) and `build/lighthouse-f0.bin` (942 float32 F0 elements).
- An earlier draft of this report mistakenly referenced a 44.1 kHz clock resulting in a 512 ms / 12,303-sample estimate; that arithmetic was incorrect and is superseded by this document.

## Full paired-teachers bank scan (Measure-PairedTeacherTicks.ps1)

Using the binary reader against the native `StudentTeacherObservation/1` format and verifying against each `kokoro.wav` header across `data/source-bank/paired-teachers`:

- **Total directories inspected**: 60
- **Verified WAV headers**: 60
- **Exact 942-tick (282,600-sample) matches in paired-teachers**: 0
- **Non-integral tick records**: 0 (all 60 records align to integer 300-sample generator frames)

### Nearest records to 942 ticks (282,600 samples)

| Id (Prefix) | Source ID | Sentence Index | Samples | Generator Ticks | Tick Delta | Execution Records |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `D4D2D716` | Gutenberg/30036 | 16 | 260,400 | 868.0 | -74 | Stock |
| `8D0A260E` | Gutenberg/30036 | 20 | 258,600 | 862.0 | -80 | None |
| `FFACC1ED` | Gutenberg/11 | 11 | 313,200 | 1,044.0 | +102 | None |
| `B124B778` | Gutenberg/30036 | 14 | 243,600 | 812.0 | -130 | Stock |
| `DD12BA97` | Gutenberg/11 | 12 | 231,000 | 770.0 | -172 | Stock |
| `5EA3C2FA` | Gutenberg/30036 | 0 | 213,000 | 710.0 | -232 | Stock |
| `AD1D309B` | Gutenberg/11 | — | 361,200 | 1,204.0 | +262 | None |
| `5E92F252` | Gutenberg/11 | — | 202,800 | 676.0 | -266 | None |

### AE6FD9EE and 032B5B23 measurements

- **`AE6FD9EE`** (Gutenberg/11 sentence 638):
  - Samples: 129,000 (5.375 s)
  - Generator ticks: 430.0
  - Tick delta from 942: **-512 ticks** (-153,600 samples)
  - Has Stock Execution: True; Has Procedural Execution: True (one of 6 retained procedural records)
- **`032B5B23`** (Gutenberg/30036 sentence 11):
  - Samples: 34,800 (1.45 s)
  - Generator ticks: 116.0
  - Tick delta from 942: **-826 ticks** (-247,800 samples)
  - Has Stock Execution: True; Has Procedural Execution: False

## Procedural execution records

Only 6 of the 60 entries retain procedural execution histories (`procedural-execution.bin`):

| Id (Prefix) | Sentence Index | Samples | Generator Ticks | Tick Delta vs 942 |
| :--- | :--- | :--- | :--- | :--- |
| `AE6FD9EE` | 638 | 129,000 | 430.0 | -512 |
| `0ED832E8` | 8 | 97,800 | 326.0 | -616 |
| `1CD6CB26` | 403 | 97,200 | 324.0 | -618 |
| `13665A25` | 24 | 68,400 | 228.0 | -714 |
| `1BF76143` | 4 | 43,800 | 146.0 | -796 |
| `18A3FE3C` | 2 | 38,400 | 128.0 | -814 |

None of the procedural entries in `paired-teachers` correspond to the 942-tick passage.

## Diagnostic implications for audio corruption

The 942-tick, 282,600-sample utterance is specifically the **Lighthouse** passage (`tools/fixtures/lighthouse-af_heart-float.wav`), which is supported by:
- `build/lighthouse-f0.bin` (942 elements)
- `build/lighthouse-input.bin` (388,032 float elements = 942 frames $\times$ 412 or 512-channel aligned representation)

The paired-teacher bank contains Gutenberg eBook material (Alice in Wonderland `Gutenberg/11` and English Grammar `Gutenberg/30036`). Searching `paired-teachers` for 942 ticks confirmed zero matches. For diagnosing corrupted phone/audio output on the lighthouse passage, comparing directly against the reference lighthouse croutons (`build/procedural-croutons.bin`) and true pitch/F0 trajectories (`build/lighthouse-true-f0.bin`) is the authoritative diagnostic path.
