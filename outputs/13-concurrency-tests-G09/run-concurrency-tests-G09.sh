#!/usr/bin/env bash
# ============================================================================
# Campus Space Management System (G09) — Concurrency Test Runner
# File: run-concurrency-tests-G09.sh
# ============================================================================
# End-to-end concurrency test execution:
#   1. Setup fixtures
#   2. Conflict pair  — two overlapping approvals launched concurrently
#   3. Non-conflict pair — two disjoint approvals launched concurrently
#   4. Verify + cleanup
# ============================================================================
# Prerequisites:
#   sqlcmd on PATH
#   05-db-definition-G09.sql
#   10-schema-migration-G09.sql
#   folder 14 data generator
#   12-concurrency-implementation-G09.sql
# ============================================================================
# Expected outcome:
#   Conflict    → one session succeeds, the other fails (Msg 50000)
#   Non-conflict → both sessions succeed
#   Verify      → "PASS: concurrency tests behave as designed."
# ============================================================================

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLCMD="sqlcmd -b"

echo "==> [1/4] Setting up fixtures"
$SQLCMD -i "$DIR/01-setup-concurrency-tests-G09.sql" || exit 1

echo "==> [2/4] CONFLICT pair — concurrent overlapping approvals"
$SQLCMD -i "$DIR/02a-session-A-conflict-G09.sql" > "$DIR/.sessA.log" 2>&1 &
PID_A=$!
$SQLCMD -i "$DIR/02b-session-B-conflict-G09.sql" > "$DIR/.sessB.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "  Session A exit=$EXIT_A   Session B exit=$EXIT_B"
grep -E "SUCCEEDED|Msg 50000|FAILED" "$DIR/.sessA.log" "$DIR/.sessB.log" || true

if [ "$EXIT_A" -eq 0 ] && [ "$EXIT_B" -eq 1 ]; then
    echo "  OK: exactly one approval succeeded (A wins)."
elif [ "$EXIT_A" -eq 1 ] && [ "$EXIT_B" -eq 0 ]; then
    echo "  OK: exactly one approval succeeded (B wins)."
else
    echo "  FAIL: unexpected exit codes A=$EXIT_A B=$EXIT_B"
    cat "$DIR/.sessA.log" "$DIR/.sessB.log"
    exit 1
fi

echo "==> [3/4] NON-CONFLICT pair — concurrent disjoint approvals"
$SQLCMD -i "$DIR/03a-session-A-nonconflict-G09.sql" > "$DIR/.sessA2.log" 2>&1 &
PID_A=$!
$SQLCMD -i "$DIR/03b-session-B-nonconflict-G09.sql" > "$DIR/.sessB2.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "  Session A exit=$EXIT_A   Session B exit=$EXIT_B"

if [ "$EXIT_A" -eq 0 ] && [ "$EXIT_B" -eq 0 ]; then
    echo "  OK: both approvals succeeded."
else
    echo "  FAIL: expected both to succeed (A=$EXIT_A B=$EXIT_B)"
    cat "$DIR/.sessA2.log" "$DIR/.sessB2.log"
    exit 1
fi

echo "==> [4/4] Verifying results and cleaning up"
$SQLCMD -i "$DIR/04-verify-and-cleanup-G09.sql" || exit 1

rm -f "$DIR/.sessA.log" "$DIR/.sessB.log" "$DIR/.sessA2.log" "$DIR/.sessB2.log"
echo "==> Concurrency tests finished."
