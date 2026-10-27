#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* || "$1" == / ]]; then
    echo "Usage: build-fedora.sh <absolute-staging-root>" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
destination=$1
mapfile -t kernels < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
if ((${#kernels[@]} == 0)); then
    echo 'morse-build: no installed kernel-core package' >&2
    exit 1
fi
headers=()
for kernel in "${kernels[@]}"; do
    [[ "$kernel" =~ ^[[:alnum:]][[:alnum:]_.+-]*$ ]] || exit 1
    headers+=("kernel-devel-$kernel")
done

dnf --disable-repo=fedora-cisco-openh264 -y --setopt=install_weak_deps=False install \
    gcc make git patch diffutils findutils kmod elfutils-libelf-devel \
    openssl-devel libnl3-devel libusb1-devel dbus-devel libpcap-devel \
    sqlite-devel pkgconf-pkg-config "${headers[@]}"

mode=stack
for kernel in "${kernels[@]}"; do
    bash "$script_dir/build.sh" "$mode" "/usr/src/kernels/$kernel" "$destination"
    mode=modules
done

install -d "$destination/usr/share/doc/morse-driver"
printf 'release=mm8108-2.1.0\ndriver=%s\nfirmware=%s\ncli=%s\nhostap=%s\n' \
    "$(git -C "$script_dir/.." rev-parse HEAD)" \
    919f27a6dc2d46a988682d6ff64dd3fdb9ffc465 \
    c0cb8a379ecd79912aefb954c00392b21e4d0b4e \
    e7309b438eaec4b82f2db29e8ef7beaca3ca52c6 \
    > "$destination/usr/share/doc/morse-driver/sources"