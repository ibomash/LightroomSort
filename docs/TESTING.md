# Lightroom Classic integration checklist

Automated tests model the SDK contract; they cannot verify the application. These
checks are pending. Use a small temporary catalog with disposable copies of photos
and record the Lightroom version and operating system when completing them.

## Installation and dialogs

- Add `DailyCollections.lrplugin` in File → Plug-in Manager. Confirm no load error
  and that the command appears under Library → Plug-in Extras.
- With no selection, confirm the selection message and no changes to the filmstrip.
- With one selected photo among many visible ones, confirm only that photo is counted.
- Select three dates. Confirm sorted rows, aligned counts, column headings, and
  keyboard tabbing. Confirm padding above the first field and below the last,
  with no duplicated collection-name previews.
- Confirm Create Collections stays disabled with any blank/whitespace-only name,
  becomes enabled while typing the last name, and trims surrounding spaces.
- Select enough dates to require scrolling. Confirm every event field is reachable.
- Cancel naming, or cancel the missing-date prompt. Confirm no catalog changes.
- Enter names for several dates, then click Preview on each. Confirm the correct
  date and only that day's selected photos in a 3×3 grid (up to nine). Return with
  Back to Naming or Escape and confirm all entered text and validation survive.
- Preview days with 1, 5, 9, and more than 9 photos. Confirm small days show all
  photos and larger days sample across capture-time order, including endpoints.
- Confirm preview rendering works for portrait and landscape photos. Check missing
  previews/offline originals and videos if used; preview failures must not alter
  labels, membership, selection, or names. Cancel naming after previewing and
  confirm no catalog changes.

## Date and hierarchy behavior

- One day: create one collection with the exact prefix and event beneath its year.
- Three days: create three collections. December/January: create two year sets.
- Reuse an existing year set and exact-name ordinary collection; preserve other
  existing collections and other events on the same date.
- Change a photo using Metadata → Edit Capture Time to a different day/year,
  without saving metadata to its original file. Confirm it appears in the edited
  day's row and resulting collection. Do not accept original-file dates here.
- Include photos just before/after midnight and with timezone offsets. Confirm
  dates match Lightroom's displayed capture dates, without conversion to Mac time.
- Include a missing-date photo if available. Confirm explicit skip warning, counts,
  and unchanged label. If every date is missing, confirm abort.
- Include selected virtual copies and videos if used in your normal workflow;
  confirm only the selected catalog objects are organized, using their shown dates.
- Confirm missing/offline originals can be organized using catalog metadata.

## Labels, membership, Undo, and failure behavior

- Use a customized color-label set with purple named “Unreviewed.” Confirm purple
  becomes genuinely unlabeled: an empty Label field and no color indicator.
  A white/custom label is not a successful substitute for no label.
- Include red, yellow, green, blue, unlabeled, and custom/white-label photos.
  Confirm those labels and their text remain unchanged.
- Include a photo already in the exact destination collection but still purple.
  Confirm no duplicate member, the purple label is cleared, and the summary counts
  it as already present and organized.
- Confirm Unicode icons render correctly, including the sun's variation selector.
- Confirm one Undo restores membership, labels, and any newly created containers.
- Create a matching smart collection or collection-set conflict. Confirm error
  before any mutation, including when the conflict is on a later selected date.
- In a disposable copy of the plugin, temporarily inject `error('test rollback')`
  after clearing a label on a later date. Confirm the entire run rolls back,
  including earlier dates and previously existing destination memberships.
  Remove the injection afterward. Never do failure injection in the main catalog.
- Confirm an error dialog does not also produce a completion dialog.

## Notes

The write callback does not catch mutation errors. This is essential for the SDK's
documented rollback behavior. Adding to a newly created collection within the same
gate is explicitly supported by the API; verify both populated collections and
their immediate display in the installed application because old versions have
had collection refresh issues.

Clearing a label can remove photos from a purple-filtered view without the plugin
changing the filter or selection itself. This is expected.
