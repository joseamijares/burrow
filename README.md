# Burrow

A calm Mac cleaner and health monitor, built on [Mole](https://github.com/tw93/Mole).

Burrow shows you every file before it moves anything. It finds caches, app leftovers, old installers, forgotten git worktrees, build folders and developer tools you don't use anymore, and it keeps an eye on memory, CPU and your network.

**[Download Burrow](https://github.com/joseamijares/burrow/releases/latest/download/Burrow.dmg)** · [Website](https://joseamijares.com/burrow) · [All releases](https://github.com/joseamijares/burrow/releases)

## Install

1. Install Mole: `brew install mole` (Burrow can also install it for you on first launch).
2. Download `Burrow.dmg`, open it and drag Burrow into Applications.
3. Open Burrow and turn on Full Disk Access when it asks. You can skip it, and Burrow will see less.

Requires macOS 14 or later. Universal (Apple silicon and Intel). Signed with a Developer ID and notarized by Apple. Burrow checks for updates once a day and installs them when you say so.

## What it does

| Tab | What it does |
| --- | --- |
| **Overview** | How much you can get back, your disk, memory and CPU, and a few things worth a look |
| **Clean** | Mole's safe caches, logs and browser data. Untick anything to keep it |
| **Apps** | Every app, with its size and when you last opened it. Uninstall lists every leftover first |
| **Tools** | Homebrew, npm, pipx, uv, cargo and nvm installs |
| **Old files** | Installers and large files you haven't opened in months |
| **Developer** | Old git worktrees, build folders, coding-agent folders and launch agents |
| **Monitor** | Memory by app, processes, network and battery |
| **Schedule** | A weekly clean that runs even when Burrow is closed, and a history of everything it did |

It also lives in the menu bar. ⌘1–⌘8 switch tabs and ⌘R scans again.

## Safety

- **Nothing is deleted without a preview.** You see the paths, the sizes and the commands, and nothing runs until you confirm.
- **The Trash, not deletion.** Old files, app leftovers, build folders and worktrees go to the Trash. Caches are deleted (apps rebuild them), and tools are removed by their own uninstaller (`brew`, `npm` and so on). The preview tells you which.
- **Never touched:** iCloud Drive and cloud folders, Photos, Mail, Messages, Keychains, `~/.ssh`, `~/.gnupg`, `.env` files and coding-agent memory.
- **Checked again just before acting.** Files that changed since the preview are skipped, and worktrees with uncommitted work stay.
- **Logged.** Every action is written to `~/Library/Application Support/Burrow/logs` before and after it runs.

## Build from source

```bash
open native/Burrow.xcworkspace                   # run the Burrow scheme (macOS 14+)
swift test --package-path native/BurrowPackage   # unit tests
```

[`native/README.md`](native/README.md) covers the architecture, the safety rules in detail, releases and updates.

## Credits

- **[Mole](https://github.com/tw93/Mole)** by tw93 does the cleaning. It's GPL-3.0, and Burrow runs it as a separate program, unmodified. Burrow is not affiliated with Mole or tw93. If you want the official Mole app, it's [Mole for Mac](https://mole.fit).
- **[Sparkle](https://sparkle-project.org)** handles updates (MIT).
- **Fonts:** Schibsted Grotesk and JetBrains Mono, under the SIL Open Font License (license files in `native/BurrowPackage/Sources/BurrowFeature/Fonts`).

## License

[MIT](LICENSE) © 2026 José Antonio Mijares
