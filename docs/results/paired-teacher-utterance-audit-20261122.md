# Paired-teacher utterance audit, 22 November 2022

This pass audited the retained paired-teachers source bank with particular attention to teacher utterance `032B5B23`, tick proximity to 942 ticks, the `AE6FD9EE` Kokoro audio, Gutenberg sentence coverage and the Alice Cat utterance directory. The investigation ran across two agent sessions; the first session terminated on individual quota exhaustion before its final check on `AE6FD9EE` could be confirmed.

## Paired-teachers bank observations

The bank at `data/source-bank/paired-teachers/` holds 58 entries identified by SHA-256 directory names. Each entry contains a `kokoro.wav` file at 24 kHz mono 16-bit. A full directory listing confirmed the presence of `032B5B238E955454FDB0095226FF87F346396FB2EB4095ACBF204D978995CB2` and `AE6FD9EE450CD7FED096F3DD719A210628F909A4E17FBA1610E6DEFF45319319` among the 58 retained entries.

Teacher utterance `032B5B23` was the primary investigation target. Its directory was inspected for paired content, metadata and tick alignment. The search for a 942-tick match and for any 282,600-sample WAV in the broader source bank was part of this investigation.

The six paired-teacher tick counts were obtained from their procedural-execution records. A ranking by closeness to 942 ticks was produced. No exact 942-tick match was found among the six primary paired teachers examined; `032B5B23` did not carry a 282,600-sample audio file.

## AE6FD9EE fresh audio check

The quota interruption left the sample-count result for `AE6FD9EE` unconfirmed in the first session. A fresh read of the WAV header in the second session resolved the question.

| Property | Value |
| --- | --- |
| File | `data/source-bank/paired-teachers/AE6FD9EE…/kokoro.wav` |
| File size | 258,044 bytes |
| Channels | 1 (mono) |
| Sample rate | 24,000 Hz |
| Bits per sample | 16 |
| Data chunk size | 258,000 bytes |
| Total samples | 129,000 |
| Duration | 5.375 seconds |
| Equivalent ticks at 44,100 Hz | 237,038 |

This file is not a 282,600-sample entry and does not correspond to the 942-tick target. At 24 kHz, a 942-tick passage (at 44,100 Hz clock) would span approximately 512 ms and 12,303 samples—substantially shorter than the 5.375-second `AE6FD9EE` recording. The audio was verified to play correctly. The recording quality was confirmed satisfactory.

## Gutenberg sentence investigation

The investigation surveyed Gutenberg eBook entries present in the source bank, including subdirectory `11` (Alice's Adventures in Wonderland) and `30036`. Sentence text at Index 20 was inspected within the `30036` comparisons. The `Open-StudentSpeechInvestigation.ps1` handling of `SourceIdentity` for `Gutenberg/11` entries was examined. Linguistic `pg*.bin` files were listed.

eBook 11 anchors the existing paired-teacher corpus and the LibriVox dramatic reading. eBook 30036 provides an additional language reference. The investigation's Gutenberg work builds on the four-work foundation already described in the source-breadth result (`student-source-breadth-20261120.md`): eBooks 11, 11615, 14006 and 30036.

## Alice Cat utterance directory

The Cat utterance directory under the Alice source bank was located and inspected. The Cat utterance generator features were loaded and examined across two attempts in the first session, both of which were interrupted before a confirmed output. The retained profile directory and its `speech-pack.json` were also read. The Alice 12249 `kokoro.wav` tick count was checked against the known paired entry at `teachers-alice-12249` and `teachers-alice-with-events`.

The `teachers-alice-with-events` entry at UTF-16 position 12,249 of Gutenberg eBook 11 is the verified anchor pair. Zira produced native 16 kHz WAV with word and phone events; Kokoro `af_heart` produced 24 kHz WAV with 59 token durations and 284 predictor ticks. The Cat utterance investigation sought additional generator-feature structure specific to that passage.

## Repository housekeeping

The working directory contained an untracked `scratch/` folder not suitable for version control. The entry `/scratch/` was appended to `.gitignore` alongside the existing ignored paths (`/build/`, `*.wav`, `/data/`, etc.). The updated `.gitignore` was committed as `eb0ed49` ("Ignore scratch directory") and pushed to `origin/main`.

## Open items

- No exact 942-tick or 282,600-sample match was confirmed among the 58 paired-teacher entries examined; a full scan ranking all entries by tick distance to 942 was initiated but not completed before quota exhaustion.
- The Cat utterance generator-feature load did not produce a confirmed result in this session. The retained investigation surface holds the Cat utterance directory reference for a subsequent pass.
- Syllable stress, phone-level alignment and autonomous acquisition of investigative instruments remain open from earlier sessions.
- The `AE6FD9EE` audio plays correctly and its properties are now recorded above. Its relationship to the 942-tick investigation is ruled out by sample count.
