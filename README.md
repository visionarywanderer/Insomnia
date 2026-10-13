<p align="center">
  <img src="docs/assets/eye-open.svg" alt="Insomnia: an open eye with a round pupil and five lashes above it" width="112">
</p>

<h1 align="center">Insomnia</h1>

<p align="center">
  <strong>Keep your Mac awake. Give the session an end time.</strong>
</p>

<p align="center">
  A macOS menu bar app for timed awake sessions. Insomnia is an eye icon that
  lives in your MacBook menu bar. It has no Dock icon and no main window. Set
  how long your Mac stays awake, choose what happens when the lid closes, and
  see when something could not be undone.
</p>

<p align="center">
  <a href="https://getinsomnia.app"><strong>Website</strong></a> ·
  <a href="#install"><strong>Install</strong></a> ·
  <a href="#using-it"><strong>Using it</strong></a> ·
  <a href="#what-happens-when-the-lid-closes"><strong>Lid close</strong></a> ·
  <a href="#how-recovery-works"><strong>Recovery</strong></a> ·
  <a href="SECURITY.md"><strong>Security</strong></a>
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/License-MIT-536D78?style=flat-square"></a>
  <img alt="macOS 26 or later" src="https://img.shields.io/badge/macOS-26%2B-303336?style=flat-square">
  <img alt="Experimental source build" src="https://img.shields.io/badge/Status-experimental-536D78?style=flat-square">
</p>

> **This is a fork of [krishhgg/Insomnia](https://github.com/krishhgg/Insomnia)**
> by Krish Garg and its contributors, under the same MIT license. It adds a
> native macOS popover, an **Auto** mode that keeps the Mac awake while Claude
> Code or Codex works and lets it sleep when they are done, and fixes for the
> lid and resume paths. All credit for the original app goes to them.

> **Use a stable, well-ventilated surface, not a closed bag.** Insomnia is
> experimental. Recovery can fail, and a running timer is not a safety
> guarantee.
> [Validation status](docs/release-validation.md) · [Apple's ventilation guidance](https://support.apple.com/en-us/102336)

## Install

Requires macOS 26 or later on an Apple Silicon Mac.

This fork publishes no releases yet: build it from source (below). The
release installer installs the original app, without this fork's changes. To
use it, paste this into your coding agent:

```text
Install the latest stable Insomnia release by following https://github.com/krishhgg/Insomnia/blob/main/skills/install-insomnia/SKILL.md. If a step needs my password, give me the command to run in Terminal.
```

For the newest nightly, write "the newest Insomnia nightly prerelease" in
place of "the latest stable Insomnia release". To install a release yourself,
follow [docs/install.md](docs/install.md).

### Build from source

Needs Xcode with Swift 6.2 or later:

```bash
git clone --depth 1 https://github.com/visionarywanderer/Insomnia.git
cd Insomnia
./scripts/install.sh
open "$HOME/Applications/Insomnia.app"
```

<details>
<summary><strong>What the installer changes on your Mac</strong></summary>

The installer needs your password, because the sudoers rule is a system
file. It installs:

- The app, at `~/Applications/Insomnia.app`.
- A **recovery agent**, a `launchd` job that runs every minute. If the app is
  gone when a session should have ended, the agent tries to undo the
  session's changes.
- A **sudoers rule** at `/etc/sudoers.d/insomnia`. A sudoers rule decides who
  can run what with `sudo`. This one lets your user account, not just
  Insomnia, run these four commands without a password:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -b lowpowermode 1
/usr/bin/pmset -b lowpowermode 0
```

Any program running as you can use that rule too, so review it before you
install. [docs/install.md](docs/install.md#what-gets-installed) lists every
file and explains how upgrades replace them.

</details>

## Using it

1. **Start.** Click the eye in the menu bar. Pick a preset, or "Until a
   time" and a time, and press Start (or Return).
2. **Add time.** Click the eye during a session and choose Extend.
3. **End early.** Click the eye and press End Session.
4. **Settings and status.** Right-click the eye. Quit asks Insomnia to undo
   the session first, and it refuses while a change is still waiting to be
   undone. Saved audio for an output that isn't connected doesn't hold it up.
   Insomnia restores that output if it reconnects while the app runs, or at
   the next launch.

### Auto: no timer

Turn on **Auto** in the popover or in Settings, then install the hooks under
Settings → Auto. Claude Code (the terminal CLI and the Claude app's Code tab)
and Codex (the CLI, the Codex app and the IDE extension) then report when they
start and stop work. While any agent works, the Mac stays awake. Once every
agent is done or waiting for you for the idle time (one minute by default),
the session ends and the Mac sleeps: always with the lid closed, and with it
open only if nobody has used the keyboard or mouse in that time.

- The hooks run `Insomnia --agent busy|idle --source claude|codex`. Installing
  keeps every other hook and setting and backs the file up once, as
  `settings.json.insomnia-backup` or `hooks.json.insomnia-backup`.
- Codex asks you to trust new hooks the first time they run.
- Plain chats in the Claude app have no hooks, so Auto cannot see them.
- An agent that crashes stops counting at once; one that never reports done
  stops counting after 30 minutes without a tool call, and an Auto session
  never runs past its ceiling (8 hours by default).
- A lid closed while an external display is connected counts as open, so a
  MacBook used in clamshell mode is never put to sleep under you.

You don't have to close the lid, and opening it doesn't end the session.
When the timer or a battery or heat rule ends a session with the lid closed,
Insomnia puts the Mac to sleep.

On battery power, Insomnia turns on Low Power Mode below 40% and ends the
session below 10%. Those are the defaults. You can change both in Settings,
and an end floor of 0 turns the battery end off. The heat rules turn on Low Power
Mode when the Mac gets seriously hot and end the session at critical heat.
They are on by default, and Settings can turn them off. All of these rules
only work while the app runs.

Before your first session, check Settings. Then run a short session you can
watch, and read `~/Library/Logs/Insomnia/insomnia.log` afterward.

## What happens when the lid closes

<p align="center">
  <img src="docs/assets/lid-actions.svg" alt="Illustrated Settings defaults: Slack, WhatsApp, and Discord on the freeze list, Docker's idle rule off, mute on. During a session, lid close applies configured actions; reopening attempts to resume verified owned freezes and restore saved audio. The session continues. Without an active session, lid changes do nothing." width="880">
</p>

During a session, closing the lid does each of these, and opening it tries
to undo them. The timer keeps counting down while the lid is closed.

- **Display and keyboard light go off.** Insomnia saves their brightness
  first. With sleep turned off, macOS no longer does this by itself.
- **Apps on the freeze list are frozen.** Freezing sends an app's processes
  `SIGSTOP`, which pauses them until `SIGCONT` on lid open. The list starts
  with Slack, WhatsApp and Discord. "Freeze every other app" is off by
  default. Even when on, it skips meeting, recording and dictation apps: Zoom,
  Teams, Webex, FaceTime, Wispr Flow, Granola, Otter, OBS and Loom.
- **Audio is muted.** Lid open unmutes each output Insomnia muted, even if you
  switched to another one.
- **Low Power Mode turns on.** It turns off when the lid opens, unless a
  battery or heat rule still needs it.
- **Docker Desktop is frozen when no container runs.** This one is off by
  default.

On Mac laptops with Apple silicon or a T2 chip, closing the lid disconnects
the built-in microphone in hardware. Recording a meeting with the lid closed
needs AirPods or an external mic.

[docs/lid-close.md](docs/lid-close.md) has the details: how Docker is checked,
how brightness is restored, the one-time settings change when you upgrade,
and how to test lid actions without closing the lid.

## How recovery works

<p align="center">
  <img src="docs/assets/recovery-flow.svg" alt="The app and a launchd backstop coordinate through a shared lock and recovery journal. The app handles normal cleanup. The backstop checks every minute and attempts due recovery, leaving valid active sessions alone. Failed or unreadable recovery evidence stays on disk; saved audio needs the app and unconfirmed stopped processes need inspection." width="880">
</p>

Insomnia writes each change to a **recovery journal**, a file on disk, before
it makes the change. Ending the session tries to undo what the journal lists.
If the app crashes or quits, the recovery agent tries the same once the
session's end time has passed.

Some things need you:

- The recovery agent can't restore audio. Open Insomnia again for that.
- The recovery agent doesn't watch the battery or the temperature.
- Insomnia only unfreezes a process it can prove it froze. A frozen process
  it can't prove stays frozen until you check it.

If the menu shows a recovery warning, deal with it before you leave the Mac
alone. [docs/recovery.md](docs/recovery.md) explains each case.

## Optional extras

<details>
<summary><strong>iPhone hotspot handoff and tmux</strong></summary>

If the Wi-Fi drops during a session, Insomnia can join your iPhone's hotspot.
Set System Settings > Wi-Fi > Ask to join hotspots to Automatically, then enter
the hotspot's name and password in Insomnia's Settings. The password stays in
your login Keychain. Insomnia asks for Location Services access, because
macOS requires it to read Wi-Fi network names. It never reads your location.
After you reinstall Insomnia, enter the password again.

After 90 seconds without a network, Insomnia can also type `continue` into a
tmux pane running a coding agent. It only types into panes you list in
Settings and mark yourself:

```bash
tmux set-option -p -t <session:window.pane> @insomnia-nudge on
```

It doesn't press Enter unless you turn that on. Mark a pane you don't type in.
[docs/extras.md](docs/extras.md) has the details.

</details>

<details>
<summary><strong>Chrome, Chromium, Arc and Comet throttling</strong></summary>

These browsers slow down windows that macOS reports as hidden, which includes
every window while the lid is closed. If a running browser lacks
`--disable-backgrounding-occluded-windows` or
`--disable-renderer-backgrounding`, the right-click menu offers "Relaunch
[browser] unthrottled". It asks first, because relaunching quits the browser,
and tabs come back only if the browser reopens them on startup. Some web apps
may still stop with the lid closed.
[docs/extras.md](docs/extras.md#chrome-chromium-arc-and-comet-throttling) has the
details.

</details>

<details>
<summary><strong>Configuration and privacy</strong></summary>

Settings live in `~/Library/Application Support/Insomnia/config.json` and logs
in `~/Library/Logs/Insomnia/`. Insomnia sets both folders and their files to
owner-only permissions. It leaves symlinks and access control lists (ACLs,
extra per-account permission entries) as they are, so another account can
still have access through one. Logs can contain Wi-Fi names, process details
and tmux targets, so check them before you share one.
[docs/extras.md](docs/extras.md#configuration-and-privacy) has the details.

</details>

## Uninstall

From your checkout:

```bash
./scripts/uninstall.sh          # removes the app, the agent and the sudoers rule
./scripts/uninstall.sh --purge  # also removes settings and logs
```

From an unpacked release zip, run `./uninstall.sh` in its folder instead. The
uninstaller undoes any open session first and stops if it can't.
[docs/install.md](docs/install.md#uninstall) has the details.

## Development

```bash
swift build
swift test
```

The tests use fakes and temporary folders, so they never change your power
settings. See [Contributing](CONTRIBUTING.md), [Security reporting](SECURITY.md),
[Release validation](docs/release-validation.md) and [Design notes](docs/spec.md).

## Star history

<a href="https://www.star-history.com/?repos=krishhgg%2FInsomnia&amp;type=date&amp;legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=krishhgg/insomnia&amp;type=date&amp;theme=dark&amp;legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=krishhgg/insomnia&amp;type=date&amp;legend=top-left" />
    <img alt="Star history for krishhgg/Insomnia" src="https://api.star-history.com/svg?repos=krishhgg/insomnia&amp;type=date&amp;legend=top-left" />
  </picture>
</a>

## License

[MIT](LICENSE)
