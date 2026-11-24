# Search and Tag UI Contract

## Navigation

- Place **Search** directly below **Home** in the sidebar.
- Keep the existing meeting list, focus behavior, and recording indicator usable while Search is active.
- Selecting Search opens one dedicated search view.

## Search controls and results

- Show a plain text field with the multi-select tag filter immediately to its right, following prototype option A.
- Update results as text changes without a submit action.
- Match title, optional meeting description, currently available transcript text, and shared tag names.
- Combine the text query and every selected tag with AND semantics. With no text, selected tags filter by themselves; with no tags selected, text alone controls matching.
- Show each matching meeting once. Include its optional description and a relevant transcript excerpt when available.
- Keep tag names and their colors consistent with the shared tag catalog.
- Show a helpful no-results state; with no text and no selected tags, show an instructional prompt.

## Meeting descriptions

- Descriptions are optional plain text.
- Provide an **Edit Description** action in the meeting's context menu. Save or cancel edits explicitly.
- Show a saved description below the meeting title on the meeting detail view and under the title in Search results.
- Empty descriptions take no space in the result row and do not add a placeholder to ordinary results.

## Tag assignment

- Provide a **Tags** action in each meeting's context menu. It opens a modal that identifies the meeting and shows currently assigned tags plus available shared tags.
- Allow selecting and deselecting assignments, creating a shared tag with a non-empty name and one palette color, then saving or cancelling the changes.
- Apply pending assignments and tag creation only on Save. Cancel leaves persisted tags and assignments unchanged.
- Show a tag icon on the right side of each sidebar meeting row that has at least one tag.

## Accessibility and responsiveness

- Search, tag filter, meeting rows, context actions, and modal controls have accessible names and keyboard focus.
- Tag identity and assignment state are available to assistive technologies without relying on color alone.
- Search must not interrupt an active recording or block normal navigation.
