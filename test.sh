#!/usr/bin/env bash
# test.sh — integration tests for the overrides/ build-time injection feature
#
# Covers all items in the PR #3 test plan:
#   1. make all builds cleanly with no overrides/ directory
#   2. make all with populated overrides/ bundles files into the data image
#   3. Init container seeds /data correctly on a fresh volume
#   4. Override files appear at the correct paths under /data
#   5. OVERRIDES_NOCLOBBER=true skips existing files and logs a warning
#   6. Default clobber mode overwrites existing files and logs a warning
#   7. Re-running on an already-seeded volume is a no-op for server files
#
# Usage:
#   ./test.sh [--skip-build]
#
#   --skip-build   Skip tests 1 & 2 (assumes images are already built).
#                  Useful when iterating on container behaviour only.

set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────

IMAGE_DATA="evilegg/all-the-mods-data:6.1"
TEST_VOL="atm10-overrides-test"
SKIP_BUILD=false

for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ── helpers ───────────────────────────────────────────────────────────────────

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

section() { echo; echo "=== $1 ==="; }

cleanup() {
    docker volume rm "$TEST_VOL" 2>/dev/null || true
    rm -rf overrides
}

# Always clean up on exit so fixture files and volumes don't linger.
trap cleanup EXIT

# ── test 1 & 2: build ─────────────────────────────────────────────────────────

if [ "$SKIP_BUILD" = false ]; then

    section "TEST 1: make all (no overrides/)"
    rm -rf overrides .build
    output=$(make all 2>&1)
    if echo "$output" | grep -q "No overrides/ directory"; then
        pass "logged 'No overrides/ directory'"
    else
        fail "expected 'No overrides/ directory' in build output"
    fi
    if echo "$output" | grep -q "Successfully built"; then
        pass "data image built successfully"
    else
        fail "data image build failed"
        echo "$output" | tail -20
    fi

    section "TEST 2: make all (with overrides/)"
    mkdir -p overrides/config overrides/mods
    printf "test-override=true\n" > overrides/config/test.properties
    printf "fake jar content\n"   > overrides/mods/test-mod.jar
    output=$(make all 2>&1)
    if echo "$output" | grep -q "Staging overrides/"; then
        pass "Makefile logged 'Staging overrides/'"
    else
        fail "expected 'Staging overrides/' in build output"
    fi
    if echo "$output" | grep -q "Successfully built"; then
        pass "data image built successfully with overrides"
    else
        fail "data image build failed"
        echo "$output" | tail -20
    fi

else
    echo "(skipping build tests — --skip-build set)"
    # Still need fixture overrides for the container tests below.
    mkdir -p overrides/config overrides/mods
    printf "test-override=true\n" > overrides/config/test.properties
    printf "fake jar content\n"   > overrides/mods/test-mod.jar
fi

# ── test 3 & 4: fresh seed ────────────────────────────────────────────────────

section "TEST 3 & 4: fresh volume — seed + override placement"
docker volume rm "$TEST_VOL" 2>/dev/null || true
seed_output=$(docker run --rm -v "$TEST_VOL":/data "$IMAGE_DATA" 2>&1)
echo "$seed_output"

if echo "$seed_output" | grep -q "Seeding /data from /opt/server"; then
    pass "seed step ran on fresh volume"
else
    fail "expected 'Seeding /data from /opt/server'"
fi

if echo "$seed_output" | grep -q "Applying overrides"; then
    pass "override step ran"
else
    fail "expected 'Applying overrides'"
fi

# Verify files in the volume
vol_check=$(docker run --rm -v "$TEST_VOL":/data alpine sh -c "
  [ -d /data/libraries ] && echo 'libraries_ok'
  [ -f /data/config/test.properties ] && echo 'config_ok'
  [ -f /data/mods/test-mod.jar ] && echo 'mods_ok'
  cat /data/config/test.properties
")

echo "$vol_check"

if echo "$vol_check" | grep -q "libraries_ok"; then
    pass "libraries/ present — server files seeded correctly"
else
    fail "libraries/ missing — server files not seeded"
fi

if echo "$vol_check" | grep -q "config_ok"; then
    pass "overrides/config/test.properties → /data/config/test.properties"
else
    fail "override file missing at /data/config/test.properties"
fi

if echo "$vol_check" | grep -q "mods_ok"; then
    pass "overrides/mods/test-mod.jar → /data/mods/test-mod.jar"
else
    fail "override file missing at /data/mods/test-mod.jar"
fi

if echo "$vol_check" | grep -q "test-override=true"; then
    pass "override file content preserved"
else
    fail "override file content wrong or missing"
fi

# ── test 5: noclobber ────────────────────────────────────────────────────────

section "TEST 5: OVERRIDES_NOCLOBBER=true skips existing files"
noclobber_output=$(docker run --rm \
    -v "$TEST_VOL":/data \
    -e OVERRIDES_NOCLOBBER=true \
    "$IMAGE_DATA" 2>&1)
echo "$noclobber_output"

if echo "$noclobber_output" | grep -q "WARNING: skipping existing file:"; then
    pass "logged 'skipping existing file' warning"
else
    fail "expected skip warning with OVERRIDES_NOCLOBBER=true"
fi

if ! echo "$noclobber_output" | grep -q "WARNING: overwriting existing file:"; then
    pass "no overwrite warning emitted"
else
    fail "should not emit overwrite warning with OVERRIDES_NOCLOBBER=true"
fi

# ── test 6: clobber ───────────────────────────────────────────────────────────

section "TEST 6: default clobber mode overwrites existing files"
clobber_output=$(docker run --rm -v "$TEST_VOL":/data "$IMAGE_DATA" 2>&1)
echo "$clobber_output"

if echo "$clobber_output" | grep -q "WARNING: overwriting existing file:"; then
    pass "logged 'overwriting existing file' warning"
else
    fail "expected overwrite warning in default mode"
fi

if ! echo "$clobber_output" | grep -q "WARNING: skipping existing file:"; then
    pass "no skip warning emitted"
else
    fail "should not emit skip warning in default clobber mode"
fi

# ── test 7: idempotency ───────────────────────────────────────────────────────

section "TEST 7: re-running on seeded volume is a no-op for server files"
rerun_output=$(docker run --rm -v "$TEST_VOL":/data "$IMAGE_DATA" 2>&1)
echo "$rerun_output"

if ! echo "$rerun_output" | grep -q "Seeding /data from /opt/server"; then
    pass "seed step skipped — volume already seeded"
else
    fail "seed step re-ran on already-seeded volume"
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
