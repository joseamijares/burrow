# Burrow for Mac

Burrow is a native Mac app that cleans and watches over your Mac. It runs
[Mole](https://github.com/tw93/Mole) (`mo`) for cleaning.
[`docs/native-swiftui-scope.md`](../docs/native-swiftui-scope.md) is the spec,
and the design is the Paper file "Burrow — Mac cleaner (powered by Mole)",
page "Burrow v2 — Jamak style". This app replaces the Claude-app prototype in
[`app/burrow.html`](../app/burrow.html). The scan scripts and parsers here are
that prototype's (v15), ported.

It comes as a disk image signed with Developer ID, with Sparkle updates, for
macOS 14 or later (universal). The build, signing, notarizing, DMG and update
setup are copied from Daybook (`daybook/mac`), with the same Apple team, the
same keychain profile and the same secret names.

## What it does

- **Window:** eight tabs.
  - **Overview:** what you can get back and the disk bar, then the next
    scheduled clean, what's worth a look, and memory and CPU right now.
  - **Clean:** Mole's dry run. Untick anything to keep it; unticked paths go
    on Mole's whitelist for that one run.
  - **Apps:** apps with when you last opened each one. Uninstall shows the
    full leftover checklist.
  - **Tools:** Homebrew, npm, pipx, uv, cargo and nvm installs.
  - **Old files:** installers, and large files you haven't opened.
  - **Developer:** worktrees, build folders, coding-agent folders and launch
    agents.
  - **Monitor:** memory, processes, network and battery.
  - **Schedule:** routines, and History.

  Use ⌘1–⌘8 to switch tabs and ⌘R to scan again.
- **Menu bar:** what you can get back, free disk, memory pressure, swap, the
  three apps using the most memory, the next clean, and shortcuts. It keeps
  running when the window is closed.
- **Its own privacy identity:** Burrow.app runs `mo`, git and the scan scripts
  as its own child processes, so they inherit Burrow's Full Disk Access. The
  prototype's "Burrow Scanner" helper is gone. On first launch Burrow checks
  for access by reading a file only Full Disk Access unlocks, and shows how to
  turn it on (with a button that opens Privacy & Security), or lets you
  continue without it. Updates keep the access, because the identity (team
  and bundle ID `com.jamak.burrow`) stays the same.
- **Mole:** Burrow uses the `mo` you installed with `brew install mole`. If
  Mole is missing, Burrow offers to install it. It shows Mole's version and,
  when there is one, offers the update. Mole is GPL-3.0; Burrow runs it as a
  separate program and credits it.

## Safety

- **Nothing is deleted without a preview.** Every destructive action builds a
  `Plan`: the paths, their sizes, and the commands to run. Burrow shows the
  plan in a confirmation sheet, and only the sheet's button turns it into an
  `Approved` plan, which is the only thing `ActionRunner` accepts. For an app
  uninstall, the leftover checklist is that preview.
- **The Trash, not deletion.** Old files, build folders, app leftovers,
  worktrees, launch agents and old agent transcripts are moved to the Trash.
  - Caches are the exception: Mole deletes those, and apps rebuild them.
  - Tools are also removed for good, because their own uninstaller (`brew`,
    `npm`, …) does the removing. The preview says so.
  - A worktree is moved to the Trash and then `git worktree prune` runs, and
    only if nothing in it is uncommitted at that moment.
- **Never touched** (`Safety.swift`, tested):
  - iCloud Drive (`~/Library/Mobile Documents`), `~/Library/CloudStorage`,
    and anything macOS reports as synced with iCloud.
  - Photos libraries, Mail, Messages, Keychains, `~/.ssh` and `~/.gnupg`.
  - `.env` files, agent memory (`~/.claude/**/memory`, `~/.codex/memories`)
    and agent settings.
  - Top-level folders such as `~`, `~/Library` and `~/Documents`.
  - Anything outside your home folder except app bundles in `/Applications`
    (never Apple's) and per-user caches in `/var/folders`.

  Clean list entries under these places are unticked, and they can't be
  ticked.
- **Checked again just before acting.** Each path is checked against the
  never-touch rules again, and old files must not have changed since the
  preview, or they're skipped.
- **Logged before and after.** Before acting, Burrow writes the plan to
  `~/Library/Application Support/Burrow/logs/<time> <kind>.json`. After, it
  adds what moved, what was skipped and why, and what failed. History links
  to that log ("Paths").
- **Mole's quirks** (lessons from the prototype):
  - Without a terminal, `mo clean` is non-interactive and empties the Trash,
    so the Trash starts unticked.
  - Each clean runs with a temporary whitelist: the paths you unticked, plus
    the cloud folders (`~/Library/CloudStorage`, `~/Library/Mobile
    Documents`). Mole's own project-cache scan looks inside those.
  - Any whitelist file switches off Mole's built-in defaults. So when you
    have no whitelist of your own, the temporary one starts from those
    defaults (read from Mole's `lib/core/base.sh`). The weekly clean's
    script does the same.
  - The temporary whitelist is journaled to `whitelist.restore.json` and put
    back after the run, or on the next launch if Burrow was quit mid-clean.
  - A worktree or folder holding a `.env` file is skipped, not moved to the
    Trash. Examples, and anything under `node_modules`, don't count.
  - `mo uninstall --with-data` keeps Group Containers, which apps from one
    developer share. Burrow lists them, unticked.
  - Spotlight may have no "last opened" date. That means "no usage record",
    never "unused".
  - Homebrew's 1985 bottle timestamps are replaced with
    `INSTALL_RECEIPT.json`'s time.
- **Google Drive prompt:** Mole's dry run looks for project build caches in
  `~/Library/CloudStorage`, so macOS may ask whether Burrow can access files
  managed by Google Drive or Dropbox. Answer **Don't Allow**: Mole then skips
  that folder, and Burrow never cleans cloud folders anyway.

## Files

| Path | What |
| --- | --- |
| `Burrow/BurrowApp.swift` | The app shell: the window, the menu bar item, Settings, Check for Updates |
| `BurrowPackage/Sources/BurrowFeature/` | Everything else |
| ↳ `Shell.swift` | Runs child processes: Burrow's PATH, stdin from `/dev/null`, timeouts, streamed lines |
| ↳ `Parsers.swift` | `clean-list.txt`, `mo status --json`, `mo uninstall --list`, the uninstall dry run, and the outputs of `oldfiles`, `devscan`, `tools`, `appfind`, `apps-meta`, `netcheck` and `ps` |
| ↳ `Engines.swift` | Mole (dry run, clean with the temporary whitelist, apps, leftovers, Homebrew cask cleanup), the scanners, and the Full Disk Access check |
| ↳ `Safety.swift`, `Actions.swift` | The never-touch rules, `Plan`/`Approved`, `ActionRunner`, History |
| ↳ `Schedule.swift` | Routines as launch agents (`com.jamak.burrow.*`) |
| ↳ `Scripts/` | The prototype's bash scripts, copied to `~/Library/Application Support/Burrow/scripts` on launch |
| ↳ `Fonts/` | Schibsted Grotesk and JetBrains Mono (SIL OFL) |
| ↳ `Theme.swift` | The Paper tokens |
| ↳ views | `RootView`, `OverviewClean`, `AppsToolsFiles`, `MonitorSchedule`, `MenuBarPanel` |
| ↳ `Updates.swift` | Sparkle; Daybook's, renamed |
| `BurrowPackage/Tests/` | Parser tests against fixtures recorded on a real Mac (home folder replaced with `/Users/you`); safety rules, the runner and the whitelist round trip, run in temporary folders; snapshots of every tab; and read-only live scans with `BURROW_LIVE=1` |
| `Config/` | Build settings, `Info.plist` (update feed and key, folder usage strings), entitlements (not sandboxed) |
| `scripts/` | `package-dmg.sh`, `signing-secrets.sh`, `export-identity.swift`, `check-update-signature.swift` (from Daybook) |
| `dmg/` | The disk image window: `settings.py` for dmgbuild, and `background.tiff` drawn by `make-background.swift` |

Burrow shares `~/Library/Application Support/Burrow` with the prototype on
purpose, so `history.jsonl` and any `com.jamak.burrow.*` routines carry over.
Its own state is in `native-state.json`.

## Build

```bash
open native/Burrow.xcworkspace                         # run the Burrow scheme (macOS 14+)
swift test --package-path native/BurrowPackage         # unit tests
SNAPSHOT_DIR=/tmp swift test --package-path native/BurrowPackage   # also renders every tab to /tmp/burrow-*.png
BURROW_LIVE=1 swift test --package-path native/BurrowPackage --filter LiveTests   # read-only scans of this Mac
```

From the command line:

```bash
xcodebuild -workspace native/Burrow.xcworkspace -scheme Burrow -derivedDataPath native/.build/dd build
open native/.build/dd/Build/Products/Debug/Burrow.app
```

A Debug build is ad-hoc signed, so macOS treats it as a different app from
the release for Full Disk Access. Test onboarding with a Developer ID build.

## Release

```bash
native/scripts/package-dmg.sh       # → native/build/Burrow-<version>.dmg (universal, ad-hoc signed)
DEVELOPER_ID="Developer ID Application: … (TEAMID)" \
  NOTARY_PROFILE=daybook native/scripts/package-dmg.sh       # signed, notarized, stapled
```

This Mac already has everything Daybook uses:

- **Signing:** the Developer ID Application identity in the login keychain.
- **Notarizing:** the `daybook` notary profile. It notarizes any app of the
  team, so Burrow reuses it.

The script signs Sparkle's helpers inside out, then the app with the hardened
runtime. Next it lays out the DMG window with dmgbuild (through `uvx` or
`pipx`), signs the image, and submits it to the notary service. It reads the
verdict, then staples. If notarizing fails, the signed image stays in
`native/build`. Once the cause is fixed, notarize that image without
rebuilding:

```bash
NOTARIZE_ONLY=1 NOTARY_PROFILE=daybook native/scripts/package-dmg.sh
```

Then check it:

```bash
xcrun stapler validate native/build/Burrow-0.1.0.dmg
spctl -a -vv native/build/dd/Build/Products/Release/Burrow.app   # "accepted, source=Notarized Developer ID"
```

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`Config/Shared.xcconfig` for each release. Sparkle compares the build number.

### From GitHub

[`.github/workflows/mac-release.yml`](../.github/workflows/mac-release.yml)
is Daybook's workflow, adapted to Burrow.

- **Tags:** pushing a `burrow-v*` tag builds, signs, notarizes and staples on
  a macOS runner. It then signs the image for Sparkle and attaches
  `Burrow-<version>.dmg` and `appcast.xml` to the tag's release. A tag with a
  suffix (`burrow-v0.2.0-beta.1`) makes a pre-release.
- **Pull requests:** a pull request that touches `native/` builds an ad-hoc
  image as a workflow artifact.
- **Secrets:** the same names as Daybook's: `DEVELOPER_ID_P12`,
  `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`,
  `NOTARY_ISSUER` (or `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`,
  `NOTARY_TEAM_ID`), and `SPARKLE_ED_PRIVATE_KEY`. Daybook's README explains
  each one.
- **Setting the secrets:** run this in the Burrow repository. It exports the
  identity, backs it up to 1Password, sets the secrets with `gh`, and then
  makes Burrow's own Sparkle key (keychain account `burrow`):

  ```bash
  NOTARY_ISSUER=<Issuer ID> native/scripts/signing-secrets.sh
  ```

## Updates

Burrow updates itself with Sparkle 2, the same version and setup as Daybook
(`Updates.swift`). The feed (`SUFeedURL` in `Config/Info.plist`) is
`https://github.com/joseamijares/burrow/releases/latest/download/appcast.xml`,
the `appcast.xml` that the release workflow attaches to the latest release.
As with Daybook, pre-releases are never "latest", so they aren't offered.
Each update has to be signed with the private half of `SUPublicEDKey`: Burrow's
own key, made by `signing-secrets.sh` (login keychain account `burrow`) and
stored in the `SPARKLE_ED_PRIVATE_KEY` secret. Keep it: installed copies only
accept updates signed with the key they shipped with. `SPARKLE_ONLY=1
native/scripts/signing-secrets.sh` sets the secret again from the keychain.

Burrow isn't sandboxed, so Sparkle installs updates directly. It needs none
of the installer-service exceptions Daybook's sandbox does. To try an update
before publishing it, launch with
`-BurrowAppcastURL http://127.0.0.1:8000/appcast.xml`, as in Daybook's
README. Launch with `-BurrowPreviewUpdate 0.9.9` to see the "update
available" state.
