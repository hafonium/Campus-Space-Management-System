#!/usr/bin/env bash
# ============================================================================
# Campus Space Management System (G09) — Concurrency test runner
# File: outputs/13-concurrency-tests-G09/run-concurrency-tests-G09.sh
# Purpose: Executes both concurrency test scenarios end-to-end:
#   1. setup fixtures
#   2. CONFLICT pair — two overlapping approvals launched concurrently
#   3. NON-CONFLICT pair — two disjoint approvals launched concurrently
#   4. verify + cleanup
# Usage:   bash outputs/13-concurrency-tests-G09/run-concurrency-tests-G09.sh
# Requires: sqlcmd on PATH (host wrapper), database CampusSpaceManagementSystem
#           with Phase 2 schema (05/06/10) and the high-volume dataset (13/14).
# Expected outcome:
#   CONFLICT    -> one session succeeds, the other fails (Msg 50000)
#   NON-CONFLICT-> both sessions succeed
#   verify      -> "PASS: concurrency tests behave as designed."
# ============================================================================

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/4] Setting up fixtures"
sqlcmd -b -i "$DIR/01-setup-concurrency-tests-G09.sql" || exit 1

echo "==> [2/4] CONFLICT pair — concurrent approvals (expect one failure)"
sqlcmd -b -i "$DIR/02a-session-A-conflict-G09.sql" > "$DIR/.sessA.log" 2>&1 &
PID_A=$!
sqlcmd -b -i "$DIR/02b-session-B-conflict-G09.sql" > "$DIR/.sessB.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "  session A exit=$EXIT_A  session B exit=$EXIT_B"
grep -E "SUCCEEDED|Msg 50000" "$DIR/.sessA.log" "$DIR/.sessB.log"
if [ "$EXIT_A" -eq 0 ] && [ "$EXIT_B" -eq 1 ]; then
    echo "  OK: exactly one approval succeeded."
elif [ "$EXIT_A" -eq 1 ] && [ "$EXIT_B" -eq 0 ]; then
    echo "  OK: exactly one approval succeeded (A failed instead)."
else
    echo "  FAIL: unexpected exit codes A=$EXIT_A B=$EXIT_B"
    exit 1
fi

echo "==> [3/4] NON-CONFLICT pair — concurrent approvals (expect both succeed)"
sqlcmd -b -i "$DIR/03a-session-A-nonconflict-G09.sql" > "$DIR/.sessA2.log" 2>&1 &
PID_A=$!
sqlcmd -b -i "$DIR/03b-session-B-nonconflict-G09.sql" > "$DIR/.sessB2.log" 2>&1 &
PID_B=$!
wait $PID_A; EXIT_A=$?
wait $PID_B; EXIT_B=$?
echo "  session A exit=$EXIT_A  session B exit=$EXIT_B"
if [ "$EXIT_A" -eq 0 ] && [ "$EXIT_B" -eq 0 ]; then
    echo "  OK: both approvals succeeded."
else
    echo "  FAIL: expected both approvals to succeed (A=$EXIT_A B=$EXIT_B)"
    exit 1
fi

echo "==> [4/4] Verifying results and cleaning up"
sqlcmd -b -i "$DIR/04-verify-concurrency-tests-G09.sql" || exit 1
rm -f "$DIR/.sessA.log" "$DIR/.sessB.log" "$DIR/.sessA2.log" "$DIR/.sessB2.log"
echo "==> Concurrency tests finished."
