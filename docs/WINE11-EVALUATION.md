# Wine 11 Evaluation

## Scope

This is a host-specific compatibility record, not a general assessment of
Wine. It records an isolated test performed on 2026-07-18 on the project's
Ubuntu 24.04 `amd64` target with SDR Console v3.4 build 3973.

The supported project path continues to use Ubuntu's standard Wine packages
(Wine 9.0 on this host). The setup script does not add the WineHQ repository or
download Wine components itself.

## Method

WineHQ Wine 11.0 was unpacked beneath a private user directory. It was not
installed with `apt`, no package source was added, and the system Wine command
was not replaced. The test used these disposable paths:

```
~/.local/share/sdr-console-wine-wine11-test/
~/.local/share/sdr-console-wine-wine11-prefix/
```

SDR Console was copied from the existing project prefix into the test prefix so
the installed application could be launched without touching the production
prefix. The required local Microsoft MFC runtime DLLs were copied only into the
test prefix after fresh Wine 11 reported `mfc140u.dll` missing. Neither those
files nor any SDR Console vendor binary are included in this repository or
changed by the project scripts.

The first Wine 11 launch was stopped after it failed to demonstrate a usable
interface. For the second launch, the copied SDR Console user configuration was
moved aside inside the test prefix. This removed saved receiver/session state
from the test while preserving it as a test-only backup. The production prefix
at `~/.local/share/sdr-console-wine/` was never changed.

Wine Mono's download prompt was cancelled. SDR Console does not require Mono
for this evaluation, and the project policy is not to download Windows or Wine
components outside the manually supplied SDR Console installer.

## Result

The second, clean-state Wine 11 launch created an `SDR Console v3.4` window but
did not become responsive. After more than one minute it had consumed roughly
one CPU core and more than 2 GiB of memory. Stopping the transient Wine 11
process did not affect the production Wine prefix.

**Decision:** Wine 11.0 is not a supported SDR Console runtime for this
project's tested host. Retain the Ubuntu 24.04 Wine 9.0 package baseline.
Reinstalling SDR Console is not expected to correct this behavior.

## Symbol Rendering Boundary

This evaluation does not change the existing font-only policy. Under Wine 9,
the bundled compatibility font restores SDR Console's `>|<`
panoramic-centering control. Some supplementary-plane menu icons can still
appear as rectangles because Wine's text path can split their UTF-16 surrogate
pairs. The project deliberately does not patch SDR Console `.exe` or `.dll`
files: such a patch would be tied to a particular vendor release and could harm
application stability.

The yellow partial-circle selection marker is SDR Console's own MFC interface
style, not a Wine rendering fault. Change it from SDR Console's **Style** menu.

## Cleanup Boundary

The two Wine 11 paths above are not created by `setup.sh` and are not needed by
normal users. They can be removed manually after SDR Console is closed. Do not
remove the production prefix, `~/.local/share/sdr-console-wine/`, unless using
the project's documented `./setup.sh --reset` or `./uninstall.sh` workflow.
