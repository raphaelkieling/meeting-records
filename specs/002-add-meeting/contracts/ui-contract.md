# UI Contract: Meeting Workspace

## Sidebar

Home and Settings remain fixed above Meetings. A plus Button next to Meetings has the accessible name and help text "Add Meeting". It is keyboard reachable with visible focus and stays outside the scrolling rows. While loading, on load failure, or during a mutation it is disabled; loading recovery uses the existing Retry flow. Once loaded, one activation creates one persisted Meeting, selects it, and reveals its first-position row.

Meeting rows remain compact, single-line, truncated with full-name help, UUID-selected, and keyboard navigable. Single click selects; double click on the name selects and starts rename. A context menu Rename action and Shift-Command-R on the focused row provide equivalent access.

## Inline rename at both locations

Choose Rename from the sidebar row’s context menu or double-click the main title to replace that text with a native field. The current name becomes the draft and the field gains focus. Expose "Meeting name" as its accessible label, with help "Enter to save. Escape to cancel." Provide a keyboard-accessible Rename context action on the main title as well.

Enter or leaving the field commits trimmed, changed input. Escape cancels. Blank input shows "Enter a meeting name." and remains editable. An embedded NUL is rejected as invalid name input. Unchanged normalized input closes editing with no save or recency update. Unicode and duplicate names are accepted.

There is one active editor. Navigation, creation, and another rename wait for its changed draft to save. Failure keeps the current destination and draft, shows an English error, and offers retry/cancel. Do not lose the old persisted name or reorder on failure. A pending save cannot be duplicated by focus loss; disable overlapping mutation controls. After success both locations show the saved name and the Meeting moves first without changing selected UUID. Preserve focus/reveal on the affected Meeting when rows reorder.

## Main content

For a Meeting, show its editable name at the top. Below it, render exactly one visibly selected tab: an SF Symbol text.alignleft plus "Transcription". Both icon and text must actually be visible on macOS 14+. The icon is decorative beside the text; accessibility announces the tab name and selection once. Content reads "No transcription yet." No Inputs, recording/import actions, transcript editing, or processing controls appear.

Home and Settings do not show Meeting title editing or Meeting tabs. Launch still selects Home. Creation/opening/editing needs no network or audio permissions.

## Errors, sizing, and focus

Mutation failures preserve the loaded list and active destination and display an understandable English error near the action/editor; retries do not duplicate an already committed creation. Existing load errors keep their separate Retry flow. Test at 720×480 and normal size, in light/dark appearance, with keyboard and VoiceOver. Focus must stay visible and must not transfer to a different UUID after sorting. Sidebar arrow navigation must not intercept TextField cursor movement while editing.
