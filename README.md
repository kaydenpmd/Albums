# Albums

A place to stash Apple Music albums you want to listen to later. It looks like Apple Music's own Library › Albums page: a two-column grid of artwork, and tapping an album opens it in Apple Music.

- **Save from Apple Music.** On an album (or a song), tap **Share**, then **Albums**. A card with the cover confirms the save, and the sheet closes itself.
- **Or paste a link.** Tap **+** in the app.
- **Tap an album** to open it in Apple Music.
- **Long-press an album** to mark it listened, share it, copy its link or delete it. The filter button shows All Albums, Not Listened or Listened.
- **Sort** from the **…** button: Recently Added, Title, Artist or Release Date. Pull down to search.

Album details come from Apple's public catalog. The lookup uses the album's ID from the link, the same exact lookup Ammy and Issun use, and never searches by name. If you share while offline, the link is saved and the details fill in the next time you open the app.

Requires iOS 26.

## Install

Albums is in **Kayden's Source**, the same one as Ammy. In SideStore, add `https://apps.kaydenpmd.net/source.json` (or open `apps.kaydenpmd.net` on the phone and tap **Add to SideStore**), then install Albums from it. New builds show up there as updates.

## Build and release

There's no Xcode project in the repo. `project.yml` describes it, and GitHub Actions builds it on a Mac.

**Pushing to `main` is releasing.** **Publish to Kayden's Source** builds the app, publishes it as a GitHub Release here, and adds it to the source in Ammy's repo, which Cloudflare Pages serves. The newest commit's message, minus its trailers, becomes What's New in SideStore. A push that only touches `**.md`, `scripts/**` or `source.config.json` doesn't release; run the workflow by hand to publish one anyway.

To build without releasing, run **Build IPA and simulator app** by hand from the Actions tab and download the `Albums-<version>-b<build>-<sha>` artifact. It's the `.ipa` itself, not a zip; in SideStore, tap **+** and pick it.

`MARKETING_VERSION` in `project.yml` is the only version number to set by hand. The build number is a commit count.

The run also uploads a simulator build (`…-simulator.zip`) for Appetize, which is handy for checking layout. The simulator has no Music app, so add albums there by pasting a link.

## Things to know

- **The first time you share,** Albums may not be in the share sheet's app row. Scroll the row to the end, tap **More**, and turn Albums on (or drag it up into Favorites).
- **When SideStore asks about app extensions, keep them.** The share extension is what puts Albums in the Share menu; remove it and you can only paste links. On a free Apple ID, app extensions count toward the three active apps, so next to SideStore and Ammy pick **Keep App Extensions (Use Main Profile)**, which doesn't take another slot. That option hasn't been tried with Albums yet: if Albums then isn't in the share sheet, or the yellow notice appears, reinstall and pick **Register App ID for Each Extension**, which needs a free slot.
- **App IDs on a free account.** A free Apple ID can register ten App IDs a week. Albums uses one, or two if its extension gets its own.
- **The yellow notice** at the top of the library means this install has no App Group, so the share sheet and the app can't see each other's albums. Reinstall with SideStore. Pasting links works either way.

## Layout

```
project.yml                           XcodeGen spec (no .xcodeproj is committed)
.github/workflows/publish-source.yml  On push to main: build, Release, add to the source
.github/workflows/build-ipa.yml       Called by the above: build, sign entitlements in, package
source.config.json                    Albums' listing in the source (user-facing copy)
Albums/                               The app: grid, add sheet
ShareExtension/                       The share sheet extension
Shared/                               Used by both: model, storage, lookup, artwork
scripts/make_icon.py                  Draws the app icon
```
