# Context for Claude Code

Albums stashes Apple Music albums to listen to later, in a grid styled like
Apple Music's Library › Albums. A share extension saves albums from the Music
app's share sheet. Bundle ID `com.local.albums`, extension
`com.local.albums.ShareExtension`, App Group `group.com.local.albums`.

The owner's ask (24 Oct 2026): "I basically just want it to just be a fancy
list of album links but it looks like it came out of the apple music app. Like
one of its two-column library pages", and "my main idea for a use case is
saving things to listen to later".

The owner works on Windows with no Mac. Like Ammy (`C:\Users\links\Repos\Ammy`),
the project is an XcodeGen `project.yml`, CI on a `macos-26` runner builds it,
and SideStore installs the `.ipa`. Nothing can be compiled locally, so CI is
the first compiler the code meets.

## Decisions

**Exact lookups only.** Album details come from iTunes Lookup by catalog ID
(`Shared/AlbumMetadataService.swift`), the same lookup Ammy and Issun use for
cover art. Never a search by name, and never guessing from a page's text: either
the ID resolves or it doesn't. Countries are tried in order: the link's
storefront, the device's region, then none. The owner: "i have a good itunes
lookup solution with ammy/issun. copy it over if you can find it. should
involve no fuzzy search".

**No accent color.** iOS 27.2 took the pink-red out of the Music app (13 Oct
2026): its icon went black and white, and its highlights went to the system's
default blue. Albums uses the default tint, and its icon is black on white
(white on black in dark mode). The icon's tiles use 60% corner smoothing, the
iOS squircle; `scripts/make_icon.py` draws it. The owner, 24 Oct 2026: "they
actually changed apple music to monochrome recently", "and this means inside
the app will use default blue accents instead of red", and of the icon, "make
sure 60% smoothing on corners".

**No album page: covers are links.** Tapping a cover opens the album in Apple
Music, and long-press holds Copy Link, Share and Delete. An album
page (big cover, tracks, Play) was built and then removed on 27 Oct 2026:
"remove the album page i just want album covers to be links to the albums".
Nothing plays inside Albums.

**One list, no listened marks.** Marking albums as listened, and the filter
for Listened and Not Listened, were removed on 2 Nov 2026: "remove the mark as
listened feature. just the main list". Libraries saved before then may still
have a `listenedAt` on each album; it's ignored when read and dropped on the
next write.

**The long-press menu copies Music's design, not its buttons.** A card with
the cover, title, artist and a ">" on top, a row of two (Copy Link, Share),
then Delete from Library on its own. Only what manages the
Albums library goes in it (owner, 1 Nov 2026: "i'm not saying copy the
buttons just the design. only have what makes sense for the library
management aspect of albums"). No Play, Shuffle or Play Next: a tap already
opens the album in Music, where Play is one more tap either way. Tapping the
card opens the album, as Music's card does ("a tap on the main card in the
long-press menu can definitely open the content full-screen"). That needs UIKit's
context menu (`willPerformPreviewActionForMenuWith`): SwiftUI's
`.contextMenu` shows the same card but can't act on a tap on it, so each grid
cell is `AlbumGridItem`, a UIKit view controller hosting the SwiftUI cell.

**Layout is measured, not guessed.** The grid follows measurements taken
from Apple's iOS 26 and 27.2 Music screenshots on a 402 pt iPhone; the numbers
are in `LibraryView`'s doc comment. All of the research is in the design
research library, `C:\Users\links\iCloudDrive\design-research\apple\ios-music-library-albums\`:
sources and versions, the images, the owner's iOS 27.2 screenshot of the
long-press menu and its measurements, and the mistakes the owner caught. Read
its `NOTES.md` before changing how Albums looks.

**Album artwork is never altered.** No fading, cropping or blending it into
anything. The album page's iOS 27-style edge-to-edge, faded cover was dropped
on 25 Oct 2026 because the owner hated it ("i hate this btw please just show
it in a square like normal"; Apple's own rules discourage altering album art
too), two days before the page itself went. Show it whole, in
a square.

## Publishing

Albums is listed in Kayden's Source (apps.kaydenpmd.net) next to Ammy. That
source is `public/source.json` in **Ammy's** repo, served by Cloudflare Pages.
Every push to `main` here that can change the app runs `publish-source.yml`:
build (via `build-ipa.yml`), a GitHub Release here that hosts the `.ipa`, then
a checkout of Ammy's repo and a run of Ammy's `scripts/build_source.py` with
Ammy's source-wide settings and this repo's `source.config.json` app block.
Pushing to `main` is releasing, and the commit message is What's New.

The README is just `# Albums`, and the listing's subtitle and description are
the owner's to write (their rule for every project, applied here on 3 Nov 2026
in `0a78c3a`). `source.config.json` keeps `"localizedDescription": ""` rather
than dropping the key, because Ammy's `build_source.py` keeps the published
text when the key is missing. Commit messages, which become What's New, are
still written as release notes.

The push into Ammy's repo uses the `SOURCE_DEPLOY_KEY` secret, an SSH deploy
key with write access to kaydenpmd/Ammy only (created 25 Oct 2026). This repo
is public because the `.ipa` has to download without a login, the same reason
Ammy's is.

`source.config.json`'s `appPermissions.entitlements` must list every
entitlement in the app and its extension. AltStore refuses to install an app
with one the source didn't declare ("undeclared permissions"). SideStore runs
the same check (`VerifyAppOperation`) only for sources with `"version": 2` or
higher, and Kayden's Source has no `version` key, so today SideStore skips it.
Don't read a SideStore install failure as a missing entitlement for that
reason. Add an entitlement in `project.yml` and it goes in the list too.

**The share extension and the free tier.** On current iOS, app extensions count
toward a free Apple ID's three active apps (SideStore's
`activeAppLimitIncludesExtensions`), so SideStore offers to strip Albums'
extension at install. Stripping it removes the share sheet entry.
"Keep App Extensions (Use Main Profile)" signs the extension with the app's
own profile, so it takes no extra slot next to SideStore and Ammy. The share
sheet works on the owner's phone (11 Nov 2026), but which of the two options
they picked isn't recorded, so whether "Use Main Profile" alone is enough is
still unverified; if it isn't, "Register App ID for Each Extension" does, at
the cost of a slot.
Publishing runs one at a time (`concurrency` in `publish-source.yml`) and only
from `main`.

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
`Artwork/<id>-<pixels>.jpg` in the same container (700 px, for the share
sheet's 220 pt card on a 3× screen), so covers the extension fetched
show in the app at once.

## Status (11 Nov 2026)

**Released:** build 6 (1.0), 2 Nov 2026, "Remove marking albums as listened".
It compiled in CI with no Swift errors or warnings, and Kayden's Source offers
it. The live listing has no subtitle or description (checked 11 Nov 2026).

**On the owner's phone:** build 6 is installed, and on 11 Nov 2026 the owner
said "it's working as intended so far". Saving from Music's share sheet works
too, so the share extension and the App Group do (which extension option was
picked at install isn't recorded; see Publishing). The first install, on 25
Oct 2026, had stopped at the free account's three active apps: SideStore,
Ammy, Tails. They didn't report on these one by one, so they're still
unconfirmed:
- The long-press menu (build 5 onward):
  - A long-press, then lifting, shouldn't open Music.
  - A scroll that starts on a cover should only scroll.
  - Tapping the card should open the album.
  - Delete should still ask first.
  - The card's dark colour should match Music's: #1C1C1D was sampled from
    Music, and the system colour is #1C1C1E, or #2C2C2E if the menu draws
    it elevated.
  - The row of two (Copy Link, Share) should look right.

**Open:**
- `AlbumActions.swift`'s doc comment calls the owner's screenshot iOS 26. It
  was iOS 27.2, the owner's phone that week. Fix it with the next code change,
  because a push that changes only a comment would still release a build.
- Logging doesn't meet the rule for every project (log everything, to a file
  that survives a crash, in every build). Albums only logs lookups, the share
  extension and the App Group check, through `os.Logger`, with no file.
