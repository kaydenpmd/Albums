# Albums

A place to stash Apple Music albums you want to listen to later. It looks like Apple Music's own Library › Albums page: a two-column grid of artwork, with each album's page laid out the way Music lays one out.

- **Save from Apple Music.** On an album (or a song), tap **Share**, then **Albums**. A card with the cover confirms the save, and the sheet closes itself.
- **Or paste a link.** Tap **+** in the app.
- **Play** opens the album in Apple Music. Tap a song to open the album at that song.
- **Listened.** Tap the checkmark on an album's page (or long-press it in the grid) to mark it listened. The filter button shows All Albums, Not Listened or Listened.
- **Sort** from the **…** button: Recently Added, Title, Artist or Release Date. Pull down to search.

Album details come from Apple's public catalog. The lookup uses the album's ID from the link, the same exact lookup Ammy and Issun use, and never searches by name. If you share while offline, the link is saved and the details fill in the next time you open the app.

Requires iOS 26.

## Build

There's no Xcode project in the repo. `project.yml` describes it, and GitHub Actions builds it on a Mac:

1. Push to `main`, or run **Build IPA and simulator app** by hand from the Actions tab.
2. When it finishes, open the run and download the `Albums-<version>-b<build>-<sha>` artifact. It's the `.ipa` itself, not a zip.
3. In SideStore, tap **+** and pick the `.ipa`.

The repo should be public: macOS runners cost 10× as many minutes on private repos.

The run also uploads a simulator build (`…-simulator.zip`) for Appetize, which is handy for checking layout. The simulator has no Music app, so add albums there by pasting a link.

## Things to know

- **The first time you share,** Albums may not be in the share sheet's app row. Scroll the row to the end, tap **More**, and turn Albums on (or drag it up into Favorites).
- **App IDs on a free account.** Albums uses two of the ten App IDs a free Apple ID gets per week (one for the app, one for its share extension). It also takes one of the three active-app slots, alongside SideStore and Ammy.
- **The yellow notice** at the top of the library means this install has no App Group, so the share sheet and the app can't see each other's albums. Reinstall with SideStore. Pasting links works either way.

## Layout

```
project.yml                      XcodeGen spec (no .xcodeproj is committed)
.github/workflows/build-ipa.yml  CI: build, sign entitlements in, package the .ipa
Albums/                          The app: grid, album page, add sheet
ShareExtension/                  The share sheet extension
Shared/                          Used by both: model, storage, lookup, artwork
scripts/make_icon.py             Draws the app icon
```
