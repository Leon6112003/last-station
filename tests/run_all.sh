#!/usr/bin/env bash
# Runs every headless test. Exits non-zero if any fail. Requires `godot` on PATH.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --import >/dev/null 2>&1
status=0
for t in tests/test_*.gd; do
  echo "=== $t ==="
  out=$(godot --headless --path . -s "res://$t" 2>&1)
  echo "$out" | grep -E "^(PASS|FAIL|ALL PASS|[0-9]+ FAILURE)"
  echo "$out" | grep -qE "^ALL PASS" || status=1
done
[ $status -eq 0 ] && echo "ALL TEST FILES PASSED" || echo "SOME TESTS FAILED"
exit $status
