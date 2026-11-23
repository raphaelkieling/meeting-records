# Audio Transcription UI Contract

## Inputs

- Keep the current Meeting Inputs list, item title, playback control, time, spacing, and ordering.
- Add exactly one transcription badge per audio Input. Its labels are `Pending`, `Transcribing`, and `Complete`.
- Show the active Recording as an Input while it is being captured so its status can move from Pending to Transcribing. Keep its existing recording indicator and playback behavior.
- Keep the existing interrupted-recording marker separate from the transcription badge.
- If the model is unavailable, keep the badge Pending and show a short explanation with a route to setup.

## Transcription

- Keep Transcription as a separate Meeting tab. It contains one unified, scrollable Meeting transcript rather than a selector that switches between per-Input transcripts.
- Include every Input's transcript once, in the existing Input order. Show a subtle Input boundary/source label so text remains attributable when a Meeting has several recordings.
- Within each Input, show available source labels (`Me` and `Other` for recordings) and timing. Preserve overlapping passages rather than hiding one.
- Append confirmed text as it arrives. Keep revisable text visually distinguishable until finalized; do not duplicate it when corrected by a later model update.
- Show a clear empty state before the first transcript segment. Show pending-work context while the latest text is behind the captured audio.
- Retain the existing Meeting shell, sidebar, tabs, active Recording control, and empty Inputs state.

## Model setup

- Settings identifies each supported local model and its download size before offering an explicit Download action. Select one installed model for new Inputs. The first installed model becomes active.
- Show download progress and whether the model is ready. Start model downloads only after explicit user action. Never send meeting audio or transcript text to a remote service.
- Once installed, model inference works offline. Before a model is installed, Record is disabled and offers a route to Settings. Previously saved audio remains intact and unfinished Inputs show Pending with an explanation.
