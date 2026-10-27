# MM8108 USB support for Fedora bootc

This branch tracks Morse Micro `mm8108-2.1.0` (driver commit
`4ce0a0272f8ac8e2fa58eea8ff08116e493399de`). It builds USB-only `morse.ko`
and `dot11ah.ko`, the matching firmware, `morse_cli`, and the suffixed S1G
hostap tools. It does not replace the Fedora kernel or normal Wi-Fi binaries.

## Review of the previous port

The reference was the local `kernel-6.17.0-14/build.md`, `build-morse.sh`,
and `patches/morse_driver/` for the preceding `mm8108-2.0.0` release.
The older `morse_driver-1.17.9` directory was already superseded there.

The 2.1.0 driver already includes equivalents of all three local kernel API
patches: the action-frame layout/size helpers, the cfg80211 station callback
adaptation, and descriptor-based device-tree GPIO lookup. Do not apply those
old patches again. In particular, retain upstream's GPIO implementation rather
than the old patch that disabled device-tree support on newer kernels.

The remaining local Kbuild fix prevents an empty `KERNEL_SRC` from emitting
a bare `-I` and swallowing the next compiler flag. Both USB modules build
against the reference 7.2 kernel. Unlike the old Debian builder, this builder
does not build a custom kernel, apply PREEMPT_RT, disable kernel signing, or
apply SDIO vendor-ID patches. Those are not required for USB.

Userspace retains the old narrow hostap unused-variable fix and OpenSSL
deprecation handling. GCC 16 defaults to C23, whose type-generic `strchr`
exposes const errors in this older hostap code; hostap is built as GNU C17.
The CLI also carries a const-correctness fix for its bundled argtable parser.
Fixed-width country codes use character initializers rather than truncated
string initializers, preserving the original regulatory table bytes.

The experimental in-tree `mm81x` driver is not this driver and must not claim
the same USB device. Check for a competing driver when changing base kernels.

## Build

Run inside the Fedora image build, using the target architecture's toolchain:

```sh
git submodule update --init --recursive
bash bootc/build-fedora.sh /out
```

The wrapper installs build dependencies and **exactly matching** `kernel-devel`
packages for every installed `kernel-core`. Old pinned Fedora images may need
a repository snapshot containing those headers. A missing exact version is a
build failure, never a reason to use the builder host's kernel or latest headers.
`JOBS` defaults to 4 and can be overridden. Builds are native to the container
architecture; use an ARM64 builder or configured binfmt emulation for ARM64.

Alternatively build a scratch artifact image with Podman or Docker:

```sh
podman build -f bootc/Containerfile -t localhost/morse-artifacts .
```

For a prepared non-Fedora kernel, stage just the modules without installing
packages or fetching userspace:

```sh
bash bootc/build.sh modules /path/to/kernel-build /tmp/morse-root
bash bootc/test-build.sh
```

Copy `/out/usr/` into a runtime image derived from the same kernel-bearing
stage, then run `depmod -a <release>` for each installed kernel. Install the
runtime RPM dependencies `libnl3`, `libusb1`, `openssl-libs`, `dbus-libs`,
`libpcap`, and `sqlite-libs`. Keep build dependencies in a discarded build stage.
Do not run DKMS or compile modules on the installed immutable system.

Sources for firmware, CLI, and hostap are pinned by commit in `build.sh`.
The firmware stage flattens the firmware and Morse Micro BCF directories into
`/usr/lib/firmware/morse`, including dereferenced boardtype aliases. Only Morse
Micro BCFs are redistributed; other vendors include files with unknown licenses.
The firmware/BCF license notices and source manifest are retained under `/usr/share`.

## Runtime and limits

USB `325b:8100` autoloads through the module alias. No forced module load or
global replacement of `wpa_supplicant` is installed. `wpa_supplicant_s1g`,
`wpa_cli_s1g`, `wpa_passphrase_s1g`, `hostapd_s1g`, and `hostapd_cli_s1g`
are available for explicit HaLow configurations; mesh is enabled in the S1G
supplicant. Normal NetworkManager connections continue using Fedora's tools.
An active S1G interface must not also be managed by the normal supplicant.

Board configuration is selected by the driver/device identity, not forced to
a particular dongle or regulatory region. If a board needs an explicit BCF,
choose the vendor-approved file and module parameters for that exact board.
Set the regulatory country in the S1G configuration appropriate to deployment.

Modules are unsigned. Secure Boot/lockdown enforcing trusted module signatures
requires signing these modules with an enrolled trusted key before copying
the artifacts. The builder does not weaken Secure Boot or kernel policy.
Rebuild the modules whenever the base image's kernel changes.

After booting an image, verify `lsusb -d 325b:8100`,
`modinfo morse`, `modinfo dot11ah`, `journalctl -k`, `iw phy`, and
`morse_cli -i <interface> version` before testing association and mesh peering.
Compilation alone does not establish hardware or radio interoperability.

## Validation

The full artifact container build has passed on the pinned Fedora 44 amd64
base, kernel `7.2.12-200.fc44.x86_64`, with GCC 16. The modules and complete
stack also build against the reference local 7.2 kernel. CI builds the same
artifact Containerfile on native amd64 and ARM64 runners; a configured CI job
is not evidence that the ARM64 run has passed. Hardware association, mesh
peering, and Secure Boot signing require separate deployment validation.