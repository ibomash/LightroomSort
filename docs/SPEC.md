# v0.1 implementation decisions

The original proposed specification is preserved in `PROPOSED_SPEC.md`. These
decisions capture the subsequent review and user clarifications:

1. One event per calendar day in a selection. Multiple same-day events are
   organized in separate runs with separate selections.
2. Collection identity is the exact complete name within its top-level year set.
   No same-date warning or matching that ignores changed status icons. This
   workflow is normally run once, before the purple “Unreviewed” label is cleared.
3. Capture dates should reflect edits made in Lightroom. Read catalog
   `dateTimeOriginalISO8601`, falling back to `dateTimeISO8601` only when the former
   cannot produce a valid date. Edit Capture Time normally updates the former;
   confirm this in the installed Lightroom version. Do not read source-file EXIF
   or convert dates to the computer's timezone.
4. Preserve the original no-selection guard. Snapshot `getTargetPhotos()` only
   after `getTargetPhoto()` establishes a real selection.
5. Process all selected photos with valid dates, including non-purple photos.
   The purple label controls label clearing, not eligibility for placement.
6. Present one scrollable naming dialog in chronological order, with date,
   photo count, and event input. Use column headings, padded rows, and no
   generated-name preview to avoid duplicating the user's input. Trim surrounding
   whitespace and reject blank or multiline/control-character names. Cancel
   changes nothing.
7. Inspect all destinations before any mutation and repeat checks inside the
   write gate. Abort on duplicate exact matches, matching smart collections,
   collection-set/collection name conflicts, or capture dates that changed
   while the dialog was open. Only inspect immediate children of each year set.
8. Use one synchronous `withWriteAccessDo` gate with a bounded ten-second write
   access wait. Let mutation errors escape the callback for full rollback.
   Never query newly created collection/set objects before commit. SDK-supported
   creation and `addPhotos` calls can share the gate.
9. Clear currently purple labels using `setRawMetadata('label', '')` after
   membership insertion succeeds (or membership already exists). Preserve every
   other label. Empty-string clearing must be verified in Lightroom.
10. Show results only after the gate returns `executed`. Organized counts include
    existing members; report new additions, purple labels cleared, created/reused
    collections, and missing-date skips separately.
11. Keep the user's source, selection, filters, and collection-panel state alone.
    Label changes may naturally affect a currently active label filter.
12. Keep the plugin self-contained. No services, AI, external processes, custom
    metadata schema, preferences, filesystem operations, or automatic import hook.
13. Each date has an optional Preview button. Open a separate modal view with up
    to nine selected photos for that day, evenly sampled from capture-time order
    with both endpoints included. Use a 3×3 grid of native `catalog_photo` views;
    show all photos when fewer than nine are selected. Preserve the naming dialog
    and its entries, with no catalog mutations or image exports while previewing.

The SDK calls require execution inside an `LrTasks` asynchronous task, with
`LrTasks.pcall` for error handling that permits SDK yields. The minimum API version
is 4.0 because the naming dialog uses `scrolled_view`; this is not a claim that
the plugin has been tested on every Lightroom release since 4.0.
