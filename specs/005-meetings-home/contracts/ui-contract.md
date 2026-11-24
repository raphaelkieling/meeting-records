# Home and Sidebar UI Contract

| Surface | Trigger | Result |
| --- | --- | --- |
| Home | Launch or select Home in the sidebar | Show up to three Meetings by creation time and two compact values labeled **Time Recorded** and **Completed Transcriptions**. |
| Home | Recording saves or recovers, a transcription completes, or a Meeting is deleted | Reflect the committed changes without a reload gesture. |
| Home | Activate a recent Meeting by mouse or keyboard | Select that Meeting in the sidebar and open Inputs. Scroll to and highlight its latest saved recording if present. Playback waits for Play. |
| Home | Library is empty | Show an empty state for recent Meetings and zero totals. |
| Home | A library read fails | Mark affected content as unavailable and offer **Try Again**. |
| Sidebar | Right-click a Meeting | Offer **Delete Meeting…**. Disable that action for the Meeting that is starting, recording, or finishing capture, and during deletion of that Meeting. |
| Confirmation dialog | Select **Delete Meeting…** | Name the Meeting and explain that its recordings, transcripts and other attached content will be permanently removed. Offer **Cancel** and a destructive **Delete**. |
| Confirmation dialog | Cancel | Close the dialog with the current selection and library intact. |
| Confirmation dialog | Confirm | Remove the Meeting and update the sidebar and Home. If it was selected, open Home. Otherwise keep the current destination. |
| Deletion error | Database write fails | Keep the Meeting and its files available and report the error. |
| Cleanup error | Files cannot be removed after the database commit | Report that removal of the files is pending and offer to retry. The Meeting has already been removed from the library. |
