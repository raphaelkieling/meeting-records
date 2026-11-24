# Quickstart: Meeting Search and Tags

## Prerequisites

- A supported Mac with Meeting Record installed.
- A local database containing meetings with distinct names, descriptions, tags, and transcript passages. Include two meetings with both `work` and `1-1`, plus meetings with only one of those tags.
- At least one meeting with an empty description and one meeting with no tags.

## Scenarios

1. Open Search from the sidebar entry immediately below Home. Confirm the text field and tag filter appear beside each other and the empty view gives an instructional prompt.
2. Search for a distinctive term in a meeting title, a saved description, a transcript passage, and a tag name. Confirm each corresponding meeting appears once. Confirm transcript matches show a relevant excerpt and non-empty descriptions appear under the meeting title.
3. Select both `work` and `1-1`. Confirm only meetings with both tags remain. Enter a text query as well and confirm results must satisfy both the text and all selected tags.
4. Clear text while keeping tag filters and confirm tag-only filtering works. Clear all selected tags and confirm text-only search works.
5. Right-click a meeting in the sidebar and open Tags. Confirm existing assignments are selected. Deselect one tag, create a new tag with a palette color, and save. Confirm the assignment and new shared tag appear in Search and the meeting row shows the tag icon.
6. Open Tags again, change a selection, then cancel. Confirm no saved assignment changed. Assign the same shared tag to another meeting and confirm its color is identical.
7. Use Edit Description from a meeting's context menu. Save a description and verify it appears under the meeting title and can be found from Search. Cancel a second edit and verify the saved text is unchanged.
8. Restart the app and confirm meeting descriptions, tag definitions, colors, and assignments persist locally.
9. Repeat search and tag actions during an active recording. Confirm recording continues and navigation remains responsive.
10. Verify a dataset of 1,000 meetings meets the spec's 1-second 95th-percentile search response target on a supported Mac.

## Expected outcome

All matching, assignment, persistence, description, and responsiveness scenarios pass while recording audio and transcripts remain intact.
