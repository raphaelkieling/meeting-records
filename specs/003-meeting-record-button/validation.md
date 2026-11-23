# Recording Validation

## Verified

- On Apple Silicon with macOS 27.2.1 and the installed Xcode Swift 6.4.2 toolchain, the app compiled with a macOS 14 deployment target. The signed debug bundle passed `codesign --verify --strict`, contained the microphone entitlement, and initialized a scratch SQLite database at launch.
- The launcher script check and all 11 Swift tests passed. Synthetic PCM tests verified two readable CAF tracks with distinct timeline offsets, recovery of a published checkpoint missing from SQLite, repeatable recovery without duplicate entries, preservation after a simulated write failure, and removal of empty starts.
- The recording lifecycle, option E control, sidebar indicator, and Inputs list compiled in the app. Transcription has an empty state.

## Pending Native Validation

- T001 — Verify the permission prompts through the actual signed app. The microphone preflight returned undetermined from the terminal. The native UI automation host failed to start.
- T002 — On a Mac with the app permissions granted, exercise simultaneous microphone and computer audio, silence on either source, permission restart behavior, and real timestamp alignment and drift. The synthetic checks validate storage offsets separately from capture-clock behavior.
- T012 — Run the interactive [validation guide](quickstart.md) for native navigation, VoiceOver, Reduce Motion, offline capture, and Force Quit during an actual recording.

## Inputs Playback

- T013–T015 — Implemented the saved segment query, AVFoundation playback, and compact cards. Inputs owns its player and calls Stop on disappearance.
- T016 — All 14 Swift tests and the signed app build passed. Saved CAF fixtures verified the decoded mix at five known points, including both sources overlapping, a silent gap, and playback of a one-track Interrupted recording. Tests also verified switching active recordings, Stop, natural completion through AVPlayer, state reset for a missing file, and byte-for-byte preservation of the original clips.
- The native automation host was unavailable. Interactive verification of the cards, leaving Inputs, and the playback controls with VoiceOver remains pending.
