# Daily Collections for Lightroom Classic

A small Lua plugin that puts selected photos into dated event collections beneath
top-level year sets, then clears purple “Unreviewed” labels.

Licensed under the [MIT License](LICENSE).

## Install

1. In Lightroom Classic, open **File → Plug-in Manager**.
2. Click **Add** and select this repository's `DailyCollections.lrplugin` folder.
3. Make sure Daily Collections is enabled, then close Plug-in Manager.
4. Select photos and run **Library → Plug-in Extras → Organize Into Daily Collections**.

The folder can stay here; Lightroom loads the plugin from the location you add.
After updating the code, use **Reload Plug-in** in Plug-in Manager (or restart
Lightroom). No Lua installation or external service is needed to use the plugin.

## Use

Enter an event name for every date in the scrollable dialog. Dates and photo counts
are read-only, with one event input per row. Create Collections
is enabled only when every name is non-empty and contains a single line. Cancel
makes no changes.

Click **Preview…** beside a date to see up to nine of that day's selected photos
in a 3×3 grid. Samples span the day in capture-time order, including the first and
last photo; days with fewer than nine show every selected photo. **Back to Naming**
returns to your existing entries. Lightroom displays the photos directly from
the catalog; no image exports or temporary files are created by the plugin.

Example:

```text
2026
  2026-09-29 ❌⭐⌫🗺🌃🖨☀️✅ Evening practice
```

- One event per date per run. For multiple events on one day, select each event's
  photos and run the command separately.
- All selected photos with usable dates are organized, regardless of label.
  Only currently purple labels are cleared. Other label text and colors are preserved.
- Capture dates come from Lightroom's catalog metadata, including changes made
  with **Metadata → Edit Capture Time**. The plugin reads `dateTimeOriginalISO8601`
  first, then `dateTimeISO8601` if necessary, and preserves the literal calendar
  date without timezone conversion. Native behavior still needs the integration
  check described below.
- Photos with missing or invalid dates are skipped only after you choose to continue.
- Existing exact-name ordinary collections are reused; existing membership is
  counted as organized. Other collections, including ones with edited status
  icons, are left alone. Rerunning after editing icons can create another collection;
  this is intentional for the once-per-import workflow.
- Destination conflicts and duplicate matches abort the operation. Collection
  creation, membership additions, and label clearing use one catalog transaction;
  errors escape the callback so Lightroom can roll back the whole run.
- The plugin does not select collections, change filters, or move files. With a
  purple-only filter active, clearing labels can naturally remove photos from view.

## Validation status

Lua 5.1 syntax and automated tests using SDK-shaped doubles pass. These tests cover
grouping, selection guards, conflict checks, label preservation, repeat membership,
cancellation, and failure/rollback control flow. They do not establish real
Lightroom SDK behavior. Native dialogs, edited capture dates, customized label
sets, empty-string label clearing, Unicode display, and actual rollback/Undo still
need testing in Lightroom Classic. See [the testing checklist](docs/TESTING.md).

## Development tests

With Lua 5.1 installed, run `lua tests/run.lua` from this folder. Alternatively, with
`uv` installed:

```sh
uv run --with lupa python - <<'PY'
from pathlib import Path
from lupa.lua51 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
for path in Path('DailyCollections.lrplugin').glob('*.lua'):
    lua.execute('assert(loadstring(...))', path.read_text())
lua.execute(Path('tests/run.lua').read_text())
PY
```

The tests need no Lightroom catalog and make no changes to your photographs.

## SDK references

The [Adobe Lightroom Classic developer page](https://developer.adobe.com/lightroom-classic)
links to the SDK. The implementation was checked against Adobe's SDK API reference
hosted on a third-party mirror:

- [LrCatalog](https://lrc.mcor.dev/modules/LrCatalog.html): selection, collection
  creation, deferred object access, write-gate status, and rollback.
- [LrCollection](https://lrc.mcor.dev/modules/LrCollection.html): membership and
  the explicit exception permitting `addPhotos` inside the creation gate.
- [LrPhoto](https://lrc.mcor.dev/modules/LrPhoto.html): ISO dates and label metadata.
- [LrDialogs](https://lrc.mcor.dev/modules/LrDialogs.html): action-button binding.
- [LrView](https://lrc.mcor.dev/modules/LrView.html): scrolling views and controls.

## Layout

```text
DailyCollections.lrplugin/
  Info.lua                   Plugin registration and Library command
  CreateDailyCollections.lua Selection, dialogs, and error handling
  Core.lua                   Date parsing, grouping, and naming
  CatalogOperations.lua      Preflight and transactional mutations
tests/run.lua                Lua 5.1 tests with SDK doubles
docs/SPEC.md                 Agreed implementation decisions
docs/TESTING.md              Lightroom integration checks
```
