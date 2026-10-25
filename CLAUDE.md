# Context for Claude Code

Albums stashes Apple Music albums to listen to later, in a grid styled like
Apple Music's Library › Albums. A share extension saves albums from the Music
app's share sheet. Bundle ID `com.local.albums`, extension
`com.local.albums.ShareExtension`, App Group `group.com.local.albums`.

The owner works on Windows with no Mac. Like Ammy (`C:\Users\links\Repos\Ammy`),
the project is an XcodeGen `project.yml`, CI on a `macos-26` runner builds it,
and SideStore installs the `.ipa`. Nothing can be compiled locally, so CI is
the first compiler the code meets.

## Decisions

**Exact lookups only.** Album details come from iTunes Lookup by catalog ID
(`Shared/AlbumMetadataService.swift`), the same lookup Ammy and Issun use for
cover art. Never a search by name, and never guessing from a page's text: either
the ID resolves or it doesn't. Countries are tried in order: the link's
storefront, the device's region, then none.

**No accent color.** iOS 27.2 took the pink-red out of the Music app (13 Oct
2026): its icon went black and white, and its highlights went to the system's
default blue. Albums uses the default tint, and its icon is black on white
(white on black in dark mode). The icon's tiles use 60% corner smoothing, the
iOS squircle; `scripts/make_icon.py` draws it.

**Play opens Apple Music.** Nothing plays inside Albums.

**Layout is measured, not guessed.** The grid and album page follow
measurements taken from Apple's iOS 26.4, 27 and 27.2 Music screenshots on a
402 pt iPhone; the numbers are in the doc comments on `LibraryView` and
`AlbumDetailView`. The album page is iOS 27's: edge-to-edge artwork fading
into a background color taken from the artwork's bottom edge, with the page
switched to light or dark to read on it (iOS 26's glass bars adapt by
themselves).

## The App Group under SideStore

This is the part that is easy to break without noticing.

1. **The entitlement has to be in the binary.** SideStore grants only the
   entitlements it finds in the app's code signature. CI builds with signing
   off, so `build-ipa.yml` ad-hoc signs (`codesign --sign -`) the extension and
   then the app with the XcodeGen-generated `.entitlements` files, and fails the
   run if the group is missing. Without that step, the share extension and the
   app each get a private library, and shared albums seem to vanish.
2. **SideStore renames the group** to `group.com.local.albums.<TEAMID>` (and the
   app to `com.local.albums.<TEAMID>`). Nothing in Info.plist says so.
   `Shared/AppGroup.swift` reads the group from the executable's own code
   signature, the way SideStore finds its own group, and falls back to names
   worked out from the bundle ID.
3. **If no group works,** the app shows a notice instead of failing quietly, and
   the share extension refuses to save.

## Storage

`Library.json` in the App Group container, written by both processes. Every
change is a coordinated read-modify-write (`NSFileCoordinator`) of the file, not
a write of what's in memory, so neither process overwrites the other's albums.
The app reloads when it becomes active. An unreadable file is moved aside
(`Library-unreadable-<time>.json`), not overwritten. Artwork is cached as
`Artwork/<id>-<pixels>.jpg` in the same container (1200 px, for the album
page's edge-to-edge cover on a 3× screen), so covers the extension fetched
show in the app at once.
