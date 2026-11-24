# Settings and Transcription Contract

| Surface | Behavior |
| --- | --- |
| Transcription Settings | Show a microphone sensitivity slider, normalized current microphone level, and a marker at the selected threshold. Label the control as affecting microphone transcription. |
| Persisted preference | Save the selected threshold locally and reuse it for the next recording. Initialize from the current near-silence behavior for existing users. |
| Me transcription | Skip below-threshold intervals, preserve a short context margin and source timestamps, and produce no text for an ineligible window. |
| Other transcription | Continue through the existing path regardless of the microphone threshold. |
| Capture | Save full Me and Other audio and publish a checkpoint every approximately ten seconds. |
| Stop or recovery | Queue and process the final partial window. Do not report complete while any eligible saved audio remains unprocessed. |

| Sidebar first Meeting row | Keep the complete keyboard focus outline inside its available bounds. |
| Home recent Meeting button | Support keyboard activation without drawing the unwanted blue outline. |
