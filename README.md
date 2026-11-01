# windows-pitfalls

**Copy-paste fixes for the Windows annoyances that have no clean answer on the internet.**
Everything here was written to fix a real problem on a real machine — no pseudo-code, no untested snippets.

Windows 11 broke my desktop repeatedly: every shortcut icon turned white, dozens of startup entries
appeared out of nowhere, batch files printed mojibake instead of Chinese, `.vbs` launchers died on
non-ASCII paths. This repo is the log of fighting each one back.

---

## Quick fixes — start here

Find your symptom, run the script. **Read the script before running it** (see [Safety](#safety)).

| Symptom | Do this |
|---|---|
| Every desktop icon turned into a blank white page | 1. `scripts/system/fix-icon-label.ps1` (repair `.lnk` targets) <br> 2. `scripts/system/rebuild-icons.bat` (rebuild `IconCache.db`, restart Explorer) |
| Shortcut names truncated / icon offset from the label | `scripts/system/fix-icon-label.ps1` |
| Too many startup apps, no idea which are safe to kill | `scripts/system/autostart-apps.ps1 -Export` — dumps every autostart surface (Run keys, services, scheduled tasks, StartupApproved) to a review file |
| A startup entry I deleted keeps coming back | `scripts/system/autostart-apps.ps1 -Verify` — idempotent re-check, reports what re-appeared |
| `.bat` prints gibberish instead of Chinese | Not a script — a rule: **batch files must be pure ASCII.** See [pitfall 2](#2-bat-files-cannot-contain-non-ascii) |
| `.vbs` launcher fails or mangles arguments on a non-ASCII path | Use a launcher from `launchers/` as a template (they resolve paths via `WScript.Shell`) |
| Launching a server shows a black console window every time | `launchers/*.vbs` — hidden-window launcher with health check before opening the browser |
| 4 identical 372 KB `.ico` files in a repo | Generate one multi-size ICO instead: `scripts/system/make-bonsai-icons.ps1` |
| A cryptominer is running (CPU pegged, unknown service) | `scripts/security/purge-miner.ps1` — **read the whole script first**, it is written for one specific sample |
| Valorant feels laggy / high ping | `scripts/system/valorant-latency-optimize.ps1` (NIC power settings, driver, priority) |

---

## The counter-intuitive stuff

These are the findings worth reading even if you do not run any script. Full write-ups in `docs/`.

### 1. White icons ≠ broken icon cache
Deleting `IconCache.db` is the advice everyone gives, and by itself it often **does not work**.
Explorer rebuilds part of the cache, and the rest still points at `.ico` files that no longer exist.

The correct order is:
1. Repair the `.lnk` files' `IconLocation` (they point at a path that moved)
2. Delete the icon cache
3. Restart Explorer

Doing 2 before 1 just makes the same broken icons faster to render.
Full root-cause chain: [`docs/README-桌面图标变白-修复经验.md`](docs/README-桌面图标变白-修复经验.md) *(Chinese)*

### 2. `.bat` files cannot contain non-ASCII
`cmd.exe` decodes batch files using the **OEM code page** (GBK on a Chinese system), not UTF-8.
A UTF-8 Chinese comment gets split into fragments and the shell tries to execute them —
`'xxx' 不是内部或外部命令`. Put human-readable comments in `.ps1` or the README, keep `.bat` pure ASCII.
This is a hard rule, not a preference: the same file works or fails depending on the code page.

### 3. `.vbs` launchers break on non-ASCII paths
When a `.lnk` passes a non-ASCII path as an argument to `wscript.exe`, the argument reaches the script
with the wrong encoding. Either keep install directories ASCII, or resolve paths inside the script with
`WScript.Shell` / `SpecialFolders` instead of letting the shortcut hardcode them.

### 4. Grep your launchers before you move a desktop file
This is the single biggest landmine in "let me tidy up my desktop". A `.lnk` points at
`DSH-Launcher.vbs`, which has `Desktop\dsh.exe` hardcoded inside it. Move `dsh.exe` and the launcher
reports *file not found* — with no obvious connection to the file you moved.

**Before moving anything off the desktop, search every `.vbs` / `.bat` / `.ps1` / `.lnk` for the name.**

### 5. "Startup apps" is four different lists, not one
The Settings page shows one list. The real autostart surface also includes:
- `HKCU` / `HKLM` `...\CurrentVersion\Run` (and `RunOnce`)
- Services set to Automatic
- Scheduled Tasks with a logon trigger
- The `StartupApproved` keys that remember what you disabled

Cleaning only the Settings list leaves everything else running.
Full audit — 49 entries reviewed, 7 kept, with a rollback script: [`docs/开机自启清理报告-20261003.md`](docs/开机自启清理报告-20261003.md) *(Chinese)*

### 6. Antivirus / driver autostart entries come back by themselves
WPS updater tasks, VPN clients and the Realtek audio service re-register themselves after removal.
One-shot cleanup is not enough — you need an **idempotent verification script** that reports what
reappeared, plus a decision each time.

---

## Repository layout

```
launchers/
  DSH-Launcher.vbs              start a server, scrape its random token from stdout,
                                health-check it, then open the browser — self-healing, no black window
  Bonsai-*.vbs                  local LLM web UI / API / stop launchers
  ComfyUI-Launcher.vbs
  QwenPaw-Launcher.vbs
  SDXL-Illustrious-Agent.vbs
  icons/                        .ico for each shortcut (incl. multi-size ICO generation)
scripts/system/
  autostart-apps.ps1/.bat       export / reconcile / trim the full autostart surface
  make-bonsai-icons.ps1         build a complete set of shortcut icons from PNG/ICO sources
  fix-icon-label.ps1/.bat       repair truncated shortcut names and misaligned icons
  rebuild-icons.bat             rebuild IconCache.db and restart Explorer
  dsh-upgrade-*.ps1             in-place upgrade: backup → replace → verify
  valorant-latency-optimize.ps1 NIC power settings, driver, priority, virtual adapters
scripts/security/
  purge-miner.ps1/.bat          cryptominer incident response: kill processes → remove disguised
                                services → block C2 → clean startup entries
docs/
  README-桌面图标变白-修复经验.md   the full white-icon root-cause chain and repair order (Chinese)
  开机自启清理报告-20261003.md      49 entries adjudicated → 7 kept, with rollback design (Chinese)
```

---

## Safety

These scripts were written for **one specific machine**. They contain hardcoded paths like
`C:\Users\<user>\...`.

- **Read before running.** Replace the paths with your own, or with `$PSScriptRoot`.
- Destructive operations (deleting startup entries, removing services, killing processes) **back up
  first** — the backup location is noted in the script comments.
- `scripts/security/purge-miner.*` was written against the specific cryptominer found on that machine.
  A different sample can cause false positives — read the kill list before executing.
- Nothing in `scripts/` needs the registry to be in a particular state, but several need an **elevated**
  shell (they say so at the top). `scripts/system/va-opt-admin.ps1` is the self-elevating wrapper.

## License

MIT — see [LICENSE](LICENSE).
