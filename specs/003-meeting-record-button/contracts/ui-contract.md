# Meeting Recording UI Contract

- **Idle** — Show Inputs first with an icon, beside Transcription. Inside the Meeting, center the icon-only Record control near the bottom. Give it a keyboard focus indicator and accessible name. Transcription shows “No transcription yet.”
- **Recording** — Expand the control into a floating pill with white waves driven by measured capture levels and a Stop icon beside them. Keep it visible across tabs and scrolling. Show a pulsing red dot on the far right of the active sidebar row and expose the recording state to assistive technologies. Reduce Motion removes the pulse and animated transitions.
- **Navigation** — Keep recording while navigating. Disable Record in other Meetings with an explanation. The active sidebar row returns the user to the Meeting to stop.
- **Finalization** — Prevent repeated start and stop requests while a transition is pending. After stop, Inputs displays the saved Recording. If either source fails during capture, end the session, preserve recoverable audio, and show the interrupted state. Explain permission and startup failures with an actionable message.
