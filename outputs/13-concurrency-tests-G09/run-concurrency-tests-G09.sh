#!/usr/bin/env bash
# ============================================================================
# Campus Space Management System (G09) — Concurrency Test Runner
# File: run-concurrency-tests-G09.sh
# ============================================================================
# Runs all three concurrency demo scenarios:
#   [1] UNSAFE  — write-skew double booking (trigger disabled, no locks)
#   [2] SAFE    — prevention with SERIALIZABLE + UPDLOCK (conflict)
#   [3] SAFE    — prevention with SERIALIZABLE + UPDLOCK (non-conflict)
# ============================================================================
# Prerequisites:
#   sqlcmd on PATH
#   05-db-definition-G09.sql
#   10-schema-migration-G09.sql
#   folder 14 data generator
#   12-concurrency-implementation-G09.sql
# ============================================================================

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLCMD="sqlcmd -b"

# ----------------------------------------------------------------------------
echo ""
echo "▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒"
echo "  CONCURRENCY TEST SUITE — G09"
echo "  Three scenarios: UNSAFE → SAFE(conflict) → SAFE(non-conflict)"
echo "▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒"
echo ""

# ============================================================================
# [1/5] UNSAFE DEMO — write-skew double booking
# ============================================================================
echo "==> [1/5] UNSAFE DEMO — conflict without locks"
echo "    (trigger DISABLED, raw UPDATE — both should succeed)"

$SQLCMD -i "$DIR/01a-demo-conflict-setup.sql" || exit 1

echo "    Launching two concurrent UNSAFE sessions..."
$SQLCMD -i "$DIR/01b-session-A-unsafe.sql" > "$DIR/.unsafeA.log" 2>&1 &
PID_A=$!
$SQLCMD -i "$DIR/01c-session-B-unsafe.sql" > "$DIR/.unsafeB.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "    Session A exit=$EXIT_A   Session B exit=$EXIT_B"

$SQLCMD -i "$DIR/01d-demo-conflict-verify.sql" || exit 1
echo ""

# ============================================================================
# [2/5] SAFE DEMO — prevention (conflicting times)
# ============================================================================
echo "==> [2/5] SAFE DEMO — prevention with SERIALIZABLE + UPDLOCK (conflict)"
echo "    (trigger ENABLED, sp_approve_booking — one expected to fail)"

echo "    Launching two concurrent SAFE sessions..."
$SQLCMD -i "$DIR/02a-session-A-safe.sql" > "$DIR/.safeA.log" 2>&1 &
PID_A=$!
$SQLCMD -i "$DIR/02b-session-B-safe.sql" > "$DIR/.safeB.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "    Session A exit=$EXIT_A   Session B exit=$EXIT_B"
grep -E "SUCCEEDED|Msg 50000|FAILED" "$DIR/.safeA.log" "$DIR/.safeB.log" || true

if [ "$EXIT_A" -eq 0 ] && [ "$EXIT_B" -eq 1 ]; then
    echo "    OK: exactly one succeeded (A wins)."
elif [ "$EXIT_A" -eq 1 ] && [ "$EXIT_B" -eq 0 ]; then
    echo "    OK: exactly one succeeded (B wins)."
else
    echo "    FAIL: unexpected exits A=$EXIT_A B=$EXIT_B"
    cat "$DIR/.safeA.log" "$DIR/.safeB.log"
    exit 1
fi

$SQLCMD -i "$DIR/02c-safe-verify.sql" || exit 1
echo ""

# ============================================================================
# [3/5] SAFE DEMO — prevention (non-conflicting times)
# ============================================================================
echo "==> [3/5] SAFE DEMO — prevention with SERIALIZABLE + UPDLOCK (non-conflict)"
echo "    (disjoint times — both should succeed, no false blocking)"

echo "    Launching two concurrent safe non-conflict sessions..."
$SQLCMD -i "$DIR/03a-session-A-safe-nonconflict.sql" > "$DIR/.ncA.log" 2>&1 &
PID_A=$!
$SQLCMD -i "$DIR/03b-session-B-safe-nonconflict.sql" > "$DIR/.ncB.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "    Session A exit=$EXIT_A   Session B exit=$EXIT_B"

if [ "$EXIT_A" -eq 0 ] && [ "$EXIT_B" -eq 0 ]; then
    echo "    OK: both succeeded."
else
    echo "    FAIL: expected both to succeed (A=$EXIT_A B=$EXIT_B)"
    cat "$DIR/.ncA.log" "$DIR/.ncB.log"
    exit 1
fi

$SQLCMD -i "$DIR/03c-safe-nonconflict-verify.sql" || exit 1
echo ""

# ============================================================================
# [4/5] Cleanup log files
# ============================================================================
rm -f "$DIR/.unsafeA.log" "$DIR/.unsafeB.log" \
      "$DIR/.safeA.log"   "$DIR/.safeB.log" \
      "$DIR/.ncA.log"     "$DIR/.ncB.log"

# ============================================================================
# [5/5] Summary
# ============================================================================
echo ""
echo "▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒"
echo "  ALL TESTS PASSED"
echo "  [1] Unsafe  → write-skew double booking CONFIRMED"
echo "  [2] Safe    → prevented by SERIALIZABLE + UPDLOCK"
echo "  [3] Safe    → non-conflicting not falsely blocked"
echo "▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒"
echo ""
