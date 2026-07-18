# SDR Console on Wine: Implementation Brief

## Objective

Provide a reproducible, low-effort installation of the Windows SDR Console
application on Linux through Wine. The repository must contain automation and
clear English documentation so users do not need an AI agent to complete setup.

## Supported Platform

- Ubuntu 24.04 LTS and current Debian/Ubuntu derivatives.
- 64-bit (`amd64`) systems only.
- A local graphical desktop session is required. Support both Wayland and X11
  without changing the user's selected display server.
- Use Ubuntu's standard `apt` Wine packages only. Do not add the WineHQ
  repository.
- Enable `i386` package architecture and install both 32-bit and 64-bit Wine
  support. The SDR Console application is 64-bit, but its NSIS setup bootstrap
  is 32-bit.

## Installer Handling

- Users manually download the desired latest stable 64-bit SDR Console
  installer from the official source.
- The user places exactly one `.exe` in
  `place-setup-exe-file-here/`.
- The script must identify a missing or ambiguous installer clearly, display
  the selected filename and SHA-256, and record both in local logs/state.
- Do not hard-code a download URL or download SDR Console.
- Do not commit or redistribute installer binaries. Add an ignore rule for
  `.exe` files in the staging directory while retaining a tracked directory
  marker/instructions.
- The project has a tested baseline release. Other user-provided releases may
  be installed but must be reported as untested rather than presented as
  guaranteed compatible.
- Before a silent install, require a one-time confirmation that the installer
  came from the official source and that the user accepts applicable vendor
  terms. Provide a documented `--yes` bypass for non-interactive automation.

## Installation Design

- The normal setup is unattended after the `sudo` password and the vendor-terms
  confirmation.
- Keep the Wine prefix, SDR Console installation, and its Windows-side state
  under `~/.local/share/sdr-console-wine/`. Never create or use a root-owned
  prefix.
- Use the installer silent mode by default. Provide `--interactive` to help
  diagnose installer or Wine regressions.
- When the full local Microsoft Webdings font is available, map it into the
  Wine prefix. This restores SDR Console's `>|<` panoramic-centering symbols,
  which Wine's compact compatibility Webdings font lacks. Provide `--fix-fonts`
  for an explicit repair after the font is installed.
- Provide a `--dpi VALUE` command that changes only the isolated SDR Console
  Wine prefix. This makes high-DPI correction reproducible and avoids users
  mistakenly changing their unrelated default `~/.wine` prefix.
- Install only named `apt` dependencies. Do not use `winetricks` or download
  Wine components from third-party sources. The manually supplied installer and
  its bundled Visual C++ redistributables are the only Windows installer input.
- Console output should show concise named phases: system checks, dependencies,
  prefix creation, installation, launcher creation, and verification. On
  failure, explain the cause and give the recovery command.
- Persist complete Wine/installer output in timestamped local logs. Keep logs
  local; no telemetry or diagnostic uploads are allowed.
- A normal rerun is idempotent: preserve a healthy installation and existing
  SDR Console settings, repairing only script-owned dependencies and launchers.
- Never update automatically. Support intentional updates through an explicit
  `--upgrade` option.
- Provide an explicit reset operation that requires confirmation before
  deleting the prefix.

## User Commands and Desktop Integration

- Create an `sdr-console` terminal command and a freedesktop `.desktop` menu
  launcher. Both must use the isolated prefix and report an incomplete
  installation helpfully.
- Do not launch SDR Console automatically after setup. Tell users how to start
  it from the menu or with `sdr-console`.
- Provide a non-destructive `--dry-run` that lists selected installer, package
  actions, prefix actions, and files to create without modifying the system.
- Provide a non-destructive `--diagnose` that checks architecture, Wine
  packages, prefix integrity, the installed executable, and launchers. It must
  not probe hardware or use the network.
- Provide an opt-in `--rtl-tcp` mode that uses an existing `rtl_tcp` command,
  or installs Ubuntu's `rtl-sdr` package when needed, and manages a per-user
  service on `127.0.0.1:1234`. This is the supported RTL-SDR path because Wine
  cannot expose the physical USB device to SDR Console's Windows USB driver.
- Provide `uninstall.sh` that removes only script-owned user state: the prefix,
  launchers, command wrapper, logs, state, and optional RTL-SDR bridge. It must
  not remove Wine or RTL-SDR `apt` packages; document optional manual package
  removal separately.

## SDR Hardware Scope

- Do not configure network interfaces, routes, PlutoSDR firmware, or any SDR
  hardware.
- Do not automatically verify PlutoSDR reachability or probe USB devices: users
  may use a different receiver.
- The first required compatibility-matrix entry is PlutoSDR over an already
  configured IP connection.
- RTL-SDR direct USB access from SDR Console under Wine is unsupported. Do not
  install Windows USB drivers or claim generic Wine USB compatibility.
- RTL-SDR is supported through the opt-in native `rtl_tcp` bridge: Linux owns
  the USB device and SDR Console connects to its localhost TCP source.
- Every other USB radio remains `not tested`. Do not add USB drivers, `udev`
  rules, or claim generic USB compatibility.
- Add USB devices to the supported matrix only after testing their exact model
  and access path on Linux/Wine.

## Documentation and Licensing

- Write an English `README.md` with a copy-paste quick start, prerequisites,
  expected prompts, usage, limitations, recovery/troubleshooting, update and
  uninstall instructions, and the hardware compatibility matrix.
- State clearly that this is an unofficial Wine setup, not affiliated with or
  supported by SDR-Radio.com, WineHQ, or radio vendors.
- State the no-telemetry/no-external-download policy (except Ubuntu package
  repositories used by `apt`).
- License repository-created scripts and documentation under MIT. SDR Console
  remains subject to its vendor's terms and is excluded from the project
  license.

## Validation Boundary

- The release success criterion is an end-to-end clean-user or disposable-VM
  test on Ubuntu 24.04: one-command setup, application startup, and reception
  from a reachable PlutoSDR over IP.
- USB receiver validation is deferred.
- Do static checks and `--dry-run` validation before any live installation.
  Installing `apt` packages or running the Windows installer on the current
  host requires separate explicit confirmation.
