#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'morse-build: %s\n' "$*" >&2; exit 1; }

if [[ $# -ne 3 || ! "$1" =~ ^(modules|stack)$ ]]; then
    echo "Usage: build.sh modules|stack <kernel-build-directory> <destination-root>" >&2
    exit 2
fi

mode=$1
kernel_build=$(realpath -- "$2")
destination=$(realpath -m -- "$3")
driver=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
jobs=${JOBS:-4}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "JOBS must be a positive integer"
[[ "$destination" != / ]] || fail "use a staging root, not /"
[[ -s "$kernel_build/Module.symvers" ]] || fail "kernel Module.symvers is missing"
[[ -s "$kernel_build/include/config/kernel.release" ]] || fail "kernel release is missing"
kernel_release=$(<"$kernel_build/include/config/kernel.release")
[[ "$kernel_release" =~ ^[[:alnum:]][[:alnum:]_.+-]*$ ]] || fail "invalid kernel release"

build_modules() {
    local output="$destination/usr/lib/modules/$kernel_release/updates/morse"
    make -C "$kernel_build" M="$driver" KERNEL_SRC="$kernel_build" \
        CONFIG_WLAN_VENDOR_MORSE=m CONFIG_MORSE_USB=y \
        CONFIG_MORSE_SDIO=n CONFIG_MORSE_SPI=n CONFIG_MORSE_VENDOR_COMMAND=y \
        CONFIG_MORSE_DEBUGFS=y CONFIG_MORSE_MONITOR=y DEBUG=n -j"$jobs" modules
    install -d "$output"
    local module vermagic
    for module in morse.ko dot11ah/dot11ah.ko; do
        vermagic=$(modinfo -F vermagic "$driver/$module")
        [[ "${vermagic%% *}" == "$kernel_release" ]] || fail "module/kernel release mismatch: $vermagic"
        install -m 0644 "$driver/$module" "$output/$(basename -- "$module")"
    done
}

fetch_source() {
    local name=$1 commit=$2
    local source="$work/$name"
    git init -q "$source"
    git -C "$source" remote add origin "https://github.com/MorseMicro/$name.git"
    git -C "$source" fetch -q --depth 1 origin "$commit"
    git -C "$source" checkout -q --detach FETCH_HEAD
    [[ "$(git -C "$source" rev-parse HEAD)" == "$commit" ]] || fail "$name revision mismatch"
}

build_cli() {
    fetch_source morse_cli c0cb8a379ecd79912aefb954c00392b21e4d0b4e
    patch -d "$work/morse_cli" -p1 < "$driver/bootc/cli-const-options.patch"
    make -C "$work/morse_cli" -j"$jobs" CONFIG_MORSE_TRANS_NL80211=1 CONFIG_MORSE_USB=1 all
    install -D -m 0755 "$work/morse_cli/morse_cli" "$destination/usr/bin/morse_cli"
    install -D -m 0644 "$work/morse_cli/LICENSING" "$destination/usr/share/licenses/morse-cli/LICENSING"
    install -D -m 0644 "$work/morse_cli/LICENSES/GPL-2.0-or-later.txt" \
        "$destination/usr/share/licenses/morse-cli/GPL-2.0-or-later.txt"
}

build_hostap() {
    fetch_source hostap e7309b438eaec4b82f2db29e8ef7beaca3ca52c6
    patch -d "$work/hostap" -p1 < "$driver/bootc/hostap-unused-variable.patch"
    patch -d "$work/hostap" -p1 < "$driver/bootc/hostap-country-codes.patch"
    local component binary
    for component in hostapd wpa_supplicant; do
        cp "$work/hostap/$component/defconfig" "$work/hostap/$component/.config"
        printf '\nCFLAGS += -std=gnu17 -Wno-error=deprecated-declarations\n' >> "$work/hostap/$component/.config"
        if [[ "$component" == wpa_supplicant ]]; then
            printf 'CONFIG_MESH=y\n' >> "$work/hostap/$component/.config"
        fi
        make -C "$work/hostap/$component" -j"$jobs"
    done
    for binary in hostapd hostapd_cli; do
        install -D -m 0755 "$work/hostap/hostapd/${binary}_s1g" "$destination/usr/sbin/${binary}_s1g"
    done
    for binary in wpa_supplicant wpa_cli wpa_passphrase; do
        install -D -m 0755 "$work/hostap/wpa_supplicant/${binary}_s1g" "$destination/usr/bin/${binary}_s1g"
    done
    install -D -m 0644 "$work/hostap/COPYING" "$destination/usr/share/licenses/morse-hostap/COPYING"
}

install_firmware() {
    fetch_source morse-firmware 919f27a6dc2d46a988682d6ff64dd3fdb9ffc465
    local source="$work/morse-firmware" file
    install -d "$destination/usr/lib/firmware/morse"
    while IFS= read -r -d '' file; do
        install -m 0644 "$file" "$destination/usr/lib/firmware/morse/$(basename -- "$file")"
    done < <(find "$source/firmware" "$source/bcf/morsemicro" -name '*.bin' -print0)
    install -D -m 0644 "$source/firmware/LICENSE" \
        "$destination/usr/share/licenses/morse-firmware/firmware-LICENSE"
    install -D -m 0644 "$source/bcf/morsemicro/LICENSE" \
        "$destination/usr/share/licenses/morse-firmware/bcf-LICENSE"
    install -D -m 0644 "$source/WHENCE.md" "$destination/usr/share/licenses/morse-firmware/WHENCE.md"
    [[ -s "$destination/usr/lib/firmware/morse/mm8108b2-rl.bin" ]] || fail "MM8108 firmware missing"
}

build_modules
if [[ "$mode" == stack ]]; then
    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT
    build_cli
    build_hostap
    install_firmware
    install -D -m 0644 "$driver/LICENSE" "$destination/usr/share/licenses/morse-driver/LICENSE"
    install -D -m 0644 "$driver/bootc/README.md" "$destination/usr/share/doc/morse-driver/README.md"
fi