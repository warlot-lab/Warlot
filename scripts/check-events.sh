#!/usr/bin/env bash
#
# The contract between the event stream and everything that reads it.
#
# `public(package)` functions raise no unused-function warning, so an emitter can
# sit with no call site indefinitely and nobody finds out. That is exactly what
# happened to three of them. This is the check that makes it impossible, and it
# runs in CI rather than being left to review.
#
# Static only: no Move toolchain, no network. Exits non-zero on the first failure.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAINNET="$ROOT/Mainnet Walrus Contract Manager/warlot protocol"
TESTNET="$ROOT/Testnet Walrus Contract Manager"

failures=0

fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
pass() { printf '  ok    %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. Every emitter has at least one call site.
# ---------------------------------------------------------------------------
echo "== emitter coverage =="
for pkg in "$MAINNET" "$TESTNET"; do
    label="$(basename "$(dirname "$pkg")")"
    [ "$label" = "$(basename "$ROOT")" ] && label="$(basename "$pkg")"

    orphans=0
    while read -r emitter; do
        [ -z "$emitter" ] && continue
        sites=$(grep -rho "\b${emitter}(" "$pkg/sources" \
                  --include='*.move' 2>/dev/null \
                | grep -cv '^$')
        declared=$(grep -rho "fun ${emitter}(" "$pkg/sources/events" \
                     --include='*.move' 2>/dev/null | wc -l)
        callers=$((sites - declared))
        if [ "$callers" -lt 1 ]; then
            fail "$label: $emitter has no call site"
            orphans=$((orphans + 1))
        else
            printf '  ok    %-42s %d call site(s)\n' "$emitter" "$callers"
        fi
    done < <(grep -rhoE '^public\(package\) fun (emit_[a-z0-9_]+)\(' \
                "$pkg/sources/events" --include='*.move' \
             | sed -E 's/^public\(package\) fun //; s/\($//')

    [ "$orphans" -eq 0 ] && pass "$label: every emitter is called"
done

# ---------------------------------------------------------------------------
# 2. Every event type is declared under sources/events/, and nowhere else.
#
# This is what lets one package-scoped event-type filter return the whole
# stream. An event declared in a domain module would still be emitted and would
# still be indexed by a package filter, but it would sit outside the surface the
# consumer contract in docs/events.md describes, so it is refused here.
# ---------------------------------------------------------------------------
echo "== event declarations =="
for pkg in "$MAINNET" "$TESTNET"; do
    label="$(basename "$pkg")"
    stray=$(grep -rln 'event::emit' "$pkg/sources" --include='*.move' 2>/dev/null \
            | grep -v '/sources/events/' || true)
    if [ -n "$stray" ]; then
        fail "$label: event::emit outside sources/events/:"
        printf '        %s\n' $stray
    else
        pass "$label: every event::emit is inside sources/events/"
    fi
done

# ---------------------------------------------------------------------------
# 3. The event modules import nothing internal, so they can never cycle.
# ---------------------------------------------------------------------------
echo "== events imports =="
for pkg in "$MAINNET" "$TESTNET"; do
    label="$(basename "$pkg")"
    internal=$(grep -rn 'use warlot::' "$pkg/sources/events" --include='*.move' || true)
    if [ -n "$internal" ]; then
        fail "$label: an event module imports from inside the package:"
        printf '        %s\n' "$internal"
    else
        pass "$label: event modules import nothing internal"
    fi
done

# ---------------------------------------------------------------------------
# 4. No bare-integer abort anywhere in sources.
#
# Two greps, because a named constant is only half the convention. The first
# refuses a literal at the abort site; the second refuses a `u64` error
# constant, which passes the first grep while still aborting as a bare number
# a caller has to look up. An `#[error] vector<u8>` carries its own message.
# ---------------------------------------------------------------------------
echo "== named aborts =="
for pkg in "$MAINNET" "$TESTNET"; do
    label="$(basename "$pkg")"
    bare=$(grep -rnE 'assert!\([^;]*,[[:space:]]*[0-9]+[[:space:]]*\)' \
             "$pkg/sources" --include='*.move' || true)
    if [ -n "$bare" ]; then
        fail "$label: bare-integer assert!:"
        printf '        %s\n' "$bare"
    else
        pass "$label: every abort is a named constant"
    fi

    numeric=$(grep -rnE '^const E[A-Za-z0-9_]*: u64' \
                "$pkg/sources" --include='*.move' || true)
    if [ -n "$numeric" ]; then
        fail "$label: error constant with no message:"
        printf '        %s\n' "$numeric"
    else
        pass "$label: every error constant carries a message"
    fi
done

# ---------------------------------------------------------------------------
# 5. Every `public(package)` function has a call site in sources/.
#
# The generalisation of check 1, and the check that would have caught the worst
# thing this script has ever missed. An emitter with no caller is one shape of
# dead code; the shape that got through was one hop further up. Nothing in
# `sources/` called `create_project_holder`, so no `ProjectHolder` could exist
# on a published package and the entire product domain was unreachable ,  while
# the emitter it called still counted as covered here, because the orphan itself
# was the call site.
#
# Neither the build nor the suite can find this. The compiler raises no unused
# warning for `public(package)`, and a test may call one directly, which is how
# the project tests built a world through a door no client could open. Call
# sites under `tests/` are therefore not counted: a function only tests reach is
# still dead on chain.
#
# The match is the name followed by `(` or `<`, so a generic call such as
# `vault::withdraw<WAL>(...)` counts as a call site.
# ---------------------------------------------------------------------------
echo "== reachable package functions =="
for pkg in "$MAINNET" "$TESTNET"; do
    label="$(basename "$pkg")"

    orphans=0
    while read -r fn; do
        [ -z "$fn" ] && continue
        uses=$(grep -rhoE "\b${fn}[[:space:]]*[(<]" \
                 "$pkg/sources" --include='*.move' | wc -l)
        declared=$(grep -rhoE "^[[:space:]]*public\(package\) fun ${fn}[[:space:]]*[(<]" \
                     "$pkg/sources" --include='*.move' | wc -l)
        if [ "$((uses - declared))" -lt 1 ]; then
            fail "$label: public(package) fun $fn has no call site in sources/"
            orphans=$((orphans + 1))
        fi
    done < <(grep -rhoE '^[[:space:]]*public\(package\) fun [a-z0-9_]+' \
                "$pkg/sources" --include='*.move' \
             | sed -E 's/.*fun //' | sort -u)

    [ "$orphans" -eq 0 ] && pass "$label: every package function is reached from sources/"
done

# ---------------------------------------------------------------------------
# 6. Both packages stay byte-identical in sources/ and tests/.
# ---------------------------------------------------------------------------
echo "== packages identical =="
for dir in sources tests; do
    if diff -r "$MAINNET/$dir" "$TESTNET/$dir" > /dev/null 2>&1; then
        pass "$dir/ is identical across both packages"
    else
        fail "$dir/ differs between the packages:"
        diff -r "$MAINNET/$dir" "$TESTNET/$dir" | sed 's/^/        /'
    fi
done

echo
if [ "$failures" -eq 0 ]; then
    echo "All event checks passed."
else
    echo "$failures check(s) failed."
fi
exit "$((failures > 0))"
