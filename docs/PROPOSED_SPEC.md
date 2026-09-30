# Lightroom Classic Daily Collection Organizer

## Purpose

Create a small Lightroom Classic Lua plugin that turns a selection of newly imported photos into date-based collections.

The user:

1. Selects a group of newly imported photos.
2. Runs a Lightroom menu command.
3. Enters a meaningful event description for each capture date represented in the selection.
4. The plugin:
   - creates/finds the appropriate year collection set;
   - creates one collection per date;
   - adds the corresponding photos;
   - removes the user's "new import" purple color label from photos successfully organized.

No network access, AI service, or external process is required.

---

## Example

Selected photos contain:

- 31 photos from September 28, 2026
- 84 photos from September 29, 2026

User invokes:

**Library → Plug-in Extras → Organize Into Daily Collections**

Dialog:

| Date | Photos | Meaningful name |
|---|---:|---|
| 2026-09-28 | 31 | Walk around town |
| 2026-09-29 | 84 | Evening practice |

Result:

Collection set:

`2026`

Collections:

`2026-09-28 ❌⭐⌫🗺🌃🖨☀️✅ Walk around town`

`2026-09-29 ❌⭐⌫🗺🌃🖨☀️✅ Evening practice`

The 31 photos from September 28 go into the first collection; the 84 photos from September 29 go into the second.

After successful collection placement, the plugin clears the purple/new-import label from those photos.

---

# Functional Requirements

## 1. Lightroom command

Install a menu command under:

**Library → Plug-in Extras → Organize Into Daily Collections**

Implementation should use the normal Lightroom Classic Lua plugin mechanism. Lightroom Classic supports Lua plugins, menu commands, metadata access, dialogs, collections, and collection sets.

Suggested plugin structure:

```text
DailyCollections.lrplugin/
    Info.lua
    CreateDailyCollections.lua
```

Additional modules may be introduced if useful, but the initial implementation should remain small.

---

## 2. Determine selected photos

Use the active Lightroom catalog.

Before calling the main logic, verify that the user actually has photos selected.

Important: `catalog:getTargetPhotos()` does not mean strictly "selected photos." When nothing is selected, Lightroom may return all photos currently visible in the filmstrip. Therefore:

1. Call `catalog:getTargetPhoto()`.
2. If it returns `nil`, abort with:
   `Select one or more photos before running Daily Collections.`
3. Otherwise use `catalog:getTargetPhotos()` to obtain the complete selection.

`getTargetPhotos()` is the appropriate SDK method once a real selection has been established.

---

## 3. Determine capture date

For each selected photo, obtain its Lightroom capture date.

Preferred metadata:

`dateTimeOriginalISO8601`

The collection date is the calendar date portion:

`YYYY-MM-DD`

For example:

`2026-09-29T16:34:02-04:00`

becomes:

`2026-09-29`

Avoid unnecessary timezone conversion; the date Lightroom reports for the photo should determine its grouping.

Fallback if `dateTimeOriginalISO8601` is unavailable:

`dateTimeISO8601`

If neither value can produce a valid date, exclude that photo from processing and report it to the user before making changes.

The SDK exposes ISO-8601 capture-time metadata through `LrPhoto`.

---

## 4. Group photos by date

Build an in-memory structure equivalent to:

```lua
groups = {
    ["2026-09-28"] = { photo1, photo2, ... },
    ["2026-09-29"] = { photo31, photo32, ... },
}
```

Sort dates ascending before displaying the dialog.

Derive the year directly from the date string:

```text
2026-09-29 → 2026
```

The plugin must support a selection spanning:

- multiple dates;
- multiple months;
- multiple years.

---

## 5. Ask for meaningful names

Show one dialog containing one text input per unique date.

Example:

```text
Create Daily Collections

2026-09-28    31 photos    [ Walk around town       ]
2026-09-29    84 photos    [ Evening practice        ]

                         Cancel     Create Collections
```

Requirements:

- Date is read-only.
- Photo count is displayed.
- Text field contains only the meaningful/event portion.
- Dates appear chronologically.
- Leading/trailing whitespace is removed.
- Every date must have a non-empty meaningful name before proceeding.
- Cancel makes no catalog changes.

A single multi-date dialog is preferred over showing one modal dialog per date.

---

# Collection Naming

## Constant status string

For v0.1, hard-code:

```text
❌⭐⌫🗺🌃🖨☀️✅
```

Define it once as a named constant:

```lua
STATUS_PREFIX = "❌⭐⌫🗺🌃🖨☀️✅"
```

Do not duplicate the literal throughout the code.

## Full collection name

Format:

```text
YYYY-MM-DD ❌⭐⌫🗺🌃🖨☀️✅ Meaningful name
```

Example:

```text
2026-09-29 ❌⭐⌫🗺🌃🖨☀️✅ Evening practice
```

There is exactly one normal space:

- after the date;
- after the final status icon.

---

# Collection Hierarchy

## Year collection sets

Each collection belongs to a top-level collection set named exactly for its year:

```text
2025
2026
2027
```

For each required year:

1. Inspect top-level collection sets.
2. Look for an exact name match.
3. If found, use it.
4. If not found, create it.

Use Lightroom's `LrCatalog` / `LrCollectionSet` APIs rather than manipulating the catalog file directly.

The SDK exposes `createCollectionSet()`, `createCollection()`, `getCollectionSets()`, and related collection APIs.

### Ambiguous year sets

If multiple top-level collection sets have the same year name, do not guess.

Abort and display an error identifying the duplicate year set.

---

# Collection Creation

For each date:

1. Determine the year collection set.
2. Build the complete collection name.
3. Check whether a collection with that exact name already exists inside the year set.
4. If it exists:
   - reuse it;
   - add the selected photos that are not already members.
5. Otherwise:
   - create it;
   - add the photos for that date.

This makes rerunning the command relatively safe.

A different collection with the same date but a different meaningful name is **not** considered a duplicate.

For example, both of these may legitimately exist:

```text
2026-09-29 ❌⭐⌫🗺🌃🖨☀️✅ School field trip
2026-09-29 ❌⭐⌫🗺🌃🖨☀️✅ Evening at home
```

Do not rename, merge, or otherwise modify existing collections in v0.1.

---

# Purple / New-Import Label

## Intent

The purple label means approximately:

> Newly imported and not yet placed into the daily collection structure.

Once a photo is successfully added to its daily collection, this state should be cleared.

## Detection

Use Lightroom's color-label metadata to determine whether the photo is currently purple.

The Lightroom SDK exposes:

```text
colorNameForLabel
```

with values including:

```text
red
yellow
green
blue
purple
none
```


## Mutation

Only clear the label when:

```text
colorNameForLabel == "purple"
```

Do **not** change photos carrying some other color label.

The writable Lightroom metadata field is:

```text
label
```

using `photo:setRawMetadata()`. This operation must occur within a catalog write-access operation.

The exact value required to represent "no label" should be verified during implementation against the current Lightroom SDK/runtime before finalizing this portion.

This is the one intentionally unresolved implementation detail in v0.1.

---

# Transaction / Safety Behavior

The critical invariant is:

> Never clear the new-import label unless the photo has successfully been placed in its intended collection.

Conceptual processing order for each date:

```text
find/create year set
        ↓
find/create collection
        ↓
add photos to collection
        ↓
clear purple label from successfully added photos
```

If collection creation or photo insertion fails, preserve the purple label.

All catalog mutations must occur through Lightroom's catalog write-access mechanisms rather than editing the `.lrcat` database directly.

`setRawMetadata()` explicitly requires a Lightroom write-access gate.

---

# Success Behavior

After processing, display a compact result dialog.

Example:

```text
Daily Collections complete

2026-09-28
31 photos → Walk around town

2026-09-29
84 photos → Evening practice

115 photos organized
112 purple labels cleared
```

No need in v0.1 to:

- navigate Lightroom to the new collections;
- change the photo selection;
- collapse/expand collection sets;
- alter Library filters.

Leave the user's Lightroom UI otherwise unchanged.

---

# Error Handling

## No selection

Abort before displaying the naming dialog.

```text
Select one or more photos before running Daily Collections.
```

## Missing capture date

Before performing writes, tell the user that some selected photos lack usable capture dates.

Prefer:

```text
3 selected photos do not have a usable capture date and cannot be organized.

Cancel
Continue with remaining 112 photos
```

If all selected photos lack dates, abort.

## Empty event name

Do not allow submission until every date has a non-empty meaningful name.

## Catalog write failure

Display the Lightroom/Lua error in a useful error dialog.

Do not continue clearing labels for affected photos.

## Existing exact collection

Reuse rather than fail.

Adding a photo already present in the collection should be harmless/idempotent.

---

# Non-Goals for v0.1

Do not implement:

- automatic execution after import;
- AI-generated event names;
- thumbnail analysis;
- GPS/location-derived names;
- renaming existing collections;
- automatic merging of same-day collections;
- configurable naming templates;
- configurable collection roots;
- preferences UI;
- cloud Lightroom integration;
- external REST APIs;
- filesystem manipulation;
- Lightroom UI automation;
- smart collections;
- automatic collection selection after completion.

These can be considered later if the basic workflow proves useful.

---

# Suggested Internal Design

Keep the implementation procedural and small.

Possible functions:

```lua
getSelectedPhotos()
getPhotoDate(photo)
groupPhotosByDate(photos)
showNamingDialog(groups)
findTopLevelCollectionSet(catalog, name)
findCollection(collectionSet, name)
ensureYearCollectionSet(catalog, year)
ensureDailyCollection(catalog, yearSet, name)
addPhotosToDailyCollection(collection, photos)
clearPurpleLabels(photos)
showSuccessDialog(results)
```

Potential main flow:

```text
main()
    ↓
verify selection
    ↓
read dates
    ↓
group by date
    ↓
show naming dialog
    ↓
user confirms
    ↓
perform catalog writes
    ↓
show result
```

Keep UI/data collection separate from catalog mutation where practical.

---

# Acceptance Criteria

The plugin is complete when all of the following work:

1. Selecting 20 photos from one day and running the command creates one correctly named collection under the correct year set.
2. Selecting photos from three different dates creates three collections after presenting three meaningful-name fields.
3. Selecting photos spanning December 2026 and January 2027 places them into separate `2026` and `2027` collection sets.
4. Missing year collection sets are created automatically.
5. Existing year collection sets are reused.
6. An existing collection with the exact generated name is reused.
7. All selected photos are placed into the appropriate date collection.
8. Purple labels are cleared after successful placement.
9. Red/yellow/green/blue labels are left untouched.
10. Canceling the naming dialog changes nothing.
11. Running the command with no actual selection does not accidentally operate on the entire filmstrip.
12. Photos lacking usable capture dates are not silently assigned to the wrong day.
13. Failure to create/add to a collection does not clear the affected photo's purple label.
14. Unicode characters in `❌⭐⌫🗺🌃🖨☀️✅` appear correctly in the resulting Lightroom collection names.

---

# Future Enhancements

Possible later improvements:

- Remember recently used event names.
- Prefill names based on nearby existing collections.
- Allow a keyboard shortcut.
- Configurable status prefix.
- Configure which color represents "unorganized."
- Warn when another collection beginning with the same date already exists.
- Automatically suggest names from filename/location/metadata.
- AI-generated event names from representative thumbnails.
- Automatically navigate to the newly created collection when only one date was processed.