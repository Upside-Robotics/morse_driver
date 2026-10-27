#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
mkdir -p "$temporary/kernel/include/config"
printf 'test-symbols\n' > "$temporary/kernel/Module.symvers"
printf '7.2.0-test\n' > "$temporary/kernel/include/config/kernel.release"

expect_failure() {
    local expected=$1
    shift
    if bash "$script_dir/build.sh" "$@" > "$temporary/output" 2>&1; then
        echo "Unexpected success: $*" >&2
        exit 1
    fi
    grep -qF "$expected" "$temporary/output"
}

expect_failure 'Usage:'
expect_failure 'staging root' modules "$temporary/kernel" /
JOBS=0 expect_failure 'positive integer' modules "$temporary/kernel" "$temporary/root"
rm "$temporary/kernel/Module.symvers"
expect_failure 'Module.symvers' modules "$temporary/kernel" "$temporary/root"
printf 'test-symbols\n' > "$temporary/kernel/Module.symvers"
printf '../bad\n' > "$temporary/kernel/include/config/kernel.release"
expect_failure 'invalid kernel release' modules "$temporary/kernel" "$temporary/root"

mkdir -p "$temporary/bin" "$temporary/driver/bootc"
cp "$script_dir/build.sh" "$temporary/driver/bootc/"
printf '7.2.0-test\n' > "$temporary/kernel/include/config/kernel.release"
cat > "$temporary/bin/make" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in M=*) driver=${argument#M=} ;; esac
done
mkdir -p "$driver/dot11ah"
printf 'module\n' > "$driver/morse.ko"
printf 'module\n' > "$driver/dot11ah/dot11ah.ko"
MOCK
cat > "$temporary/bin/modinfo" <<'MOCK'
#!/usr/bin/env bash
printf '%s SMP\n' "${TEST_VERMAGIC:-7.2.0-test}"
MOCK
chmod +x "$temporary/bin/make" "$temporary/bin/modinfo"
export PATH="$temporary/bin:$PATH"
bash "$temporary/driver/bootc/build.sh" modules "$temporary/kernel" "$temporary/root"
test -s "$temporary/root/usr/lib/modules/7.2.0-test/updates/morse/morse.ko"
test -s "$temporary/root/usr/lib/modules/7.2.0-test/updates/morse/dot11ah.ko"
if TEST_VERMAGIC=wrong-kernel bash "$temporary/driver/bootc/build.sh" modules \
    "$temporary/kernel" "$temporary/bad-root" > "$temporary/output" 2>&1; then
    echo 'Mismatched kernel module was accepted' >&2
    exit 1
fi
grep -qF 'module/kernel release mismatch' "$temporary/output"
echo 'morse builder tests passed'