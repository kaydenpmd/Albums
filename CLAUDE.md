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

**No album page: covers are links.** Tapping a cover opens the album in Apple
Music, and long-press holds Listened, Share, Copy Link and Delete. An album
page (big cover, tracks, Play) was built and then removed on 27 Oct 2026, the
owner's call. Nothing plays inside Albums.

**Layout is measured, not guessed.** The grid follows measurements taken
from Apple's iOS 26 and 27.2 Music screenshots on a 402 pt iPhone; the numbers
are in `LibraryView`'s doc comment.

**Album artwork is never altered.** No fading, cropping or blending it into
anything. The album page's iOS 27-style edge-to-edge, faded cover was dropped
on 25 Oct 2026 because the owner hated it (and Apple's own rules discourage
altering album art), two days before the page itself went. Show it whole, in
a square.

## Publishing

Albums is listed in Kayden's Source (apps.kaydenpmd.net) next to Ammy. That
source is `public/source.json` in **Ammy's** repo, served by Cloudflare Pages.
Every push to `main` here that can change the app runs `publish-source.yml`:
build (via `build-ipa.yml`), a GitHub Release here that hosts the `.ipa`, then
a checkout of Ammy's repo and a run of Ammy's `scripts/build_source.py` with
Ammy's source-wide settings and this repo's `source.config.json` app block.
Pushing to `main` is releasing, and the commit message is What's New.

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
own profile, so it takes no extra slot next to SideStore and Ammy. Whether the
share extension and App Group work that way is unverified on a phone; if they
don't, "Register App ID for Each Extension" does, at the cost of a slot.
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
