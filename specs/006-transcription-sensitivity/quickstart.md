# Validate Microphone Transcription Sensitivity

On an Apple Silicon Mac running macOS 14 or later, install a transcription model through Settings. Keep the validation library disposable.

From the repository root, run:

\`\`\`sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
./run
\`\`\`

1. Open Settings and watch the microphone meter while silent, speaking normally, and speaking softly. Move the threshold between room noise and normal speech, close and reopen Settings, and verify the value persists.
2. Record low-level background noise and normal speech. Verify the transcript excludes below-threshold input and includes speech above it. Play the saved recording and confirm all original microphone audio remains.
3. Record a short phrase near a threshold boundary and a sentence with short pauses. Verify words near crossings and pauses remain intelligible, ordered, and timestamped.
4. Record continuous speech for at least 25 seconds. Verify live transcription becomes available in approximately ten-second windows and continues during capture.
5. Stop with a partial final phrase. Verify the phrase is transcribed and the recording reaches Complete.
6. Use a recording with independent Other-track speech while raising the microphone threshold above all Me input. Verify Other remains transcribed.
7. Recover a disposable interrupted recording containing multiple checkpoints. Verify all saved intervals are processed exactly once and progress completes.

Document threshold, model, observed meter levels, test phrases, output, OS and remaining word loss or hallucination examples here after real-device validation.

## Automated Validation

**Date**: 2026-11-23  
**Environment**: Apple Silicon, macOS 27.2 SDK, Swift 6, Xcode 27.2 toolchain  
**Command**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --scratch-path .build/feature-006-baseline`  
**Result**: 22 tests passed, including RMS and threshold interval boundaries, unchanged Other-track selection, ten-second checkpoint publication, adjacent legacy checkpoint batching, independent source progress, partial checkpoint recovery and timestamp preservation.

**Manual speech calibration**: Pending. No threshold value, model output, or real microphone speech result has been recorded yet. Complete the scenarios above with the installed local model before judging word loss or hallucination rates.
