# SDR Console on Wine

Unofficial scripts for installing the Windows SDR Console application on Linux
in an isolated Wine prefix. This project is not affiliated with or supported by
SDR-Radio.com, WineHQ, or radio hardware vendors.

The project scripts and documentation are [MIT licensed](LICENSE). SDR Console
is proprietary software and remains subject to its vendor's terms; its installer
is not included or redistributed here.

## Supported Scope

- Ubuntu 24.04 LTS is the tested platform target. Current Debian/Ubuntu
  derivatives on 64-bit (`amd64`) systems are accepted but should be validated
  before being called supported.
- A local graphical desktop session is required to run SDR Console. Wayland and
  X11 are both intended to work without changing the user's desktop settings.
- Wine comes only from the standard `apt` repositories. Setup enables `i386`
  packages and installs both 32-bit and 64-bit Wine support because the SDR
  Console setup program is 32-bit while the application is 64-bit.
- The first intended radio path is an already configured PlutoSDR over IP. The
  scripts do not alter networks, probe radios, or change PlutoSDR firmware.
- RTL-SDR and all other USB receivers are **not tested**. The project does not
  install USB drivers or `udev` rules and makes no generic USB compatibility
  claim.

## Quick Start

1. Download the desired latest stable **64-bit** SDR Console Windows installer
   from its official source.
2. Put exactly one `.exe` file in
   [`place-setup-exe-file-here/`](place-setup-exe-file-here/). The installer is
   ignored by Git.
3. From this directory, review the planned actions:

   ```bash
   ./setup.sh --dry-run
   ```

4. Install it as your normal desktop user. Do **not** prepend `sudo`:

   ```bash
   ./setup.sh
   ```

   The script asks you to confirm that you obtained the installer from the
   official source and accept its terms, then requests your `sudo` password
   only when Wine packages must be installed.
5. Start SDR Console from the desktop application menu or run:

   ```bash
   sdr-console
   ```

Setup creates the Wine prefix and SDR Console settings in
`~/.local/share/sdr-console-wine/`. It does not start SDR Console automatically.
If `~/.local/bin` is not on your `PATH`, open a new terminal session or use the
application-menu launcher.

## Commands

| Command | Purpose |
| --- | --- |
| `./setup.sh` | Install, or repair a matching existing installation. |
| `./setup.sh --dry-run` | Inspect installer selection, packages, and generated files without changing anything. |
| `./setup.sh --diagnose` | Check Wine packages, prefix, executable, and launchers without probing hardware. |
| `./setup.sh --interactive` | Show the Windows installer instead of using silent mode. |
| `./setup.sh --upgrade` | Intentionally install a different staged installer. Normal reruns never upgrade automatically. |
| `./setup.sh --reset` | Remove the isolated installation and all SDR Console settings after confirmation. |
| `./uninstall.sh` | Remove project-owned prefix, launchers, logs, and state after confirmation. |
| `./uninstall.sh --dry-run` | List the files that uninstall would remove. |

`--yes` bypasses the vendor-terms confirmation in setup and the destructive
confirmation in reset/uninstall. It is intended only for deliberate automation.

## What Setup Changes

The setup script displays progress for system checks, dependencies, Wine-prefix
creation, SDR Console installation, launcher creation, and verification.

- It uses `apt` only when Wine packages are missing. The required packages are
  `wine`, `wine64`, and `wine32:i386`; enabling `i386` is a system-wide package
  setting.
- It uses the manually supplied installer and does not download SDR Console,
  Wine components, or Windows runtime installers from third-party sources.
- Full setup output is written locally to
  `${XDG_STATE_HOME:-~/.local/state}/sdr-console-wine/logs/`.
- It creates `~/.local/bin/sdr-console` and a desktop-menu launcher. Both use
  the isolated prefix.
- It does not collect, send, or upload diagnostics or usage data. Apart from
  `apt` package downloads, the scripts make no network requests.

The provided installer file name and SHA-256 are recorded in local state. A
release becomes a tested baseline only after the validation below; any other
single staged installer is installable but is not implicitly certified by this
project.

## Compatibility Matrix

| Receiver path | First-release status | Notes |
| --- | --- | --- |
| PlutoSDR over IP | Target for validation | Network configuration is the user's responsibility; setup does not probe it. |
| RTL-SDR over USB | Not tested | Deferred; no drivers or access rules are installed. |
| Other USB receivers | Not tested | Add only after testing the exact model and Linux/Wine access path. |

## Updates, Recovery, and Removal

Normal reruns preserve a healthy installation and SDR Console settings. If the
SHA-256 of the staged installer differs from the recorded one, setup stops and
requires `--upgrade`; this avoids surprise updates.

For a broken installation, run `./setup.sh --diagnose` first. It checks only
local state and does not connect to an SDR. Use `./setup.sh --interactive` when
the silent Windows installer needs investigation.

`./setup.sh --reset` and `./uninstall.sh` remove the Wine prefix, application
settings, local state/logs, and launchers. They deliberately leave Wine's `apt`
packages installed because they may be shared by other applications. Users who
installed Wine only for this project can review and run `sudo apt autoremove`
themselves.

## Release Validation

Before claiming a tested release, validate it on a clean Ubuntu 24.04 user
account or disposable VM: one-command setup, application startup, and signal
reception through an already reachable PlutoSDR over IP. USB validation remains
separate and device-specific.
