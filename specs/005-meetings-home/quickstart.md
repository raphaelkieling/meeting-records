# Validate Meetings Home

Use a test library on an Apple Silicon Mac running macOS 14 or later with Swift 6. Install the existing transcription model in Settings before validating capture or transcription. Create disposable Meetings for the deletion checks.

From the repository root, run with the full Xcode toolchain selected:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
./run
```

1. **Recent Meetings** — Create four Meetings, leaving the newest empty. Rename and add a recording to the oldest. Open Home. It shows the three newest by creation time. Open the empty Meeting and verify Inputs is empty.
2. **Latest recording** — Save several recordings in a recent Meeting. Open it from Home using the mouse, then return and open it with the keyboard. Both times, Inputs makes its latest saved recording visible and highlights it. Audio starts when you select Play.
3. **Automatic totals** — Note both values on Home. Start a recording, return to Home, and confirm the displayed saved duration stays steady during capture. Stop the recording in its Meeting and return to Home. The displayed duration includes the new recording. Leave Home open while a queued transcription completes. The count increases without a refresh. For a saved recording with overlapping tracks, compare the time increase to its playback duration.
4. **Delete a Meeting** — Use the sidebar context menu to delete a disposable recent Meeting with saved audio and a completed transcript. Cancel the first dialog and verify it still opens. Confirm on the second attempt while that Meeting is selected. Verify Home opens, the next recent Meeting fills the slot, and the totals fall by the deleted Meeting's contributions. Relaunch and verify the Meeting's recording directory and related records are gone. Repeat with a different Meeting selected and verify the selection stays intact.
5. **Capture and cleanup** — While a disposable Meeting is recording, verify its Delete action is disabled. Stop and verify deletion becomes available after saving. Exercise the failure paths with temporary storage fixtures.
   - Force the deletion transaction to fail and verify the Meeting and files remain available.
   - Simulate a process exit after deletion commits and before file cleanup finishes. Reopen the store, run cleanup and verify it removes the directory. Verify repeating cleanup is safe.
   - Submit a late transcript result for the deleted Meeting. Verify that it adds no data and that another Meeting's work completes.
6. **Recovery and offline use** — Recover an interrupted recording in a disposable library. Verify its contribution is its saved playback duration, including after reopening. Disconnect from the network and verify Home and its navigation still work.

See [the UI contract](contracts/ui-contract.md) for the expected states and [the data model](data-model.md) for storage invariants.

## Validation on 2026-11-23

- **Environment** — MacBook Pro with Apple M4 Max, macOS 27.2.1, Swift 6.4.2 from full Xcode. The app bundle built and launched against a disposable database.
- **Native check** — The Home list followed creation order even though the oldest Meeting was updated last. The fixture showed 18 seconds and two completed transcriptions across nine recordings, including audio outside the recent list. Mouse and keyboard activation opened Inputs and scrolled to the highlighted eighth recording. Opening an empty Meeting showed the Inputs empty state. The sidebar offered Delete Meeting, the dialog named the target, and cancelling preserved the selection and totals.
- **Automated checks** — All 16 Swift tests passed. Coverage includes v4 migration, saved and recovered durations, exclusion during capture, the background transcription completion signal, deletion and totals, database rollback, cleanup retry after reopen, and stale transcription results. The Home store read also passed with network access denied.
- **Remaining native checks** — Run a live microphone and system capture with the transcription model installed, observe both Home values during a real capture and transcription cycle, and confirm deletion from the native dialog using a disposable Meeting. The confirmed deletion path was exercised at the store and file layers.
