#!/usr/bin/env bash
# Scenario tests for the hhkb-caps-ctrl preset (presets/hhkb-caps-ctrl/apply.sh).
# Runs against disposable copies; --template <file> overrides the pristine oracle.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATE="${TEMPLATE:-}"
ORACLE="$REPO_ROOT/default-toshy-config/toshy_config.py"
APPLY="$SCRIPT_DIR/../apply.sh"
PY="${TOSHY_PYTHON:-$HOME/.config/toshy/.venv/bin/python}"
[[ -x "$PY" ]] || PY=python3

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -n "$TEMPLATE" ]] && ORACLE="$TEMPLATE"
cp "$ORACLE" "$TMP/original.py"
cp "$ORACLE" "$TMP/fresh.py"

echo "== S1: fresh apply → markers + compiles =="
bash "$APPLY" --target "$TMP/fresh.py" --no-fcitx5 --skip-restart >"$TMP/s1.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "S1 exit 0" || bad "S1 exit=$rc (log: $TMP/s1.log)"
m=$(grep -c "PRESET: hhkb-caps-ctrl (modmap)" "$TMP/fresh.py" || true)
[[ "$m" -eq 2 ]] && ok "S1 modmap markers ==2" || bad "S1 modmap markers=$m expect 2"
k=$(grep -c "PRESET: hhkb-caps-ctrl (keymap)" "$TMP/fresh.py" || true)
[[ "$k" -eq 2 ]] && ok "S1 keymap markers ==2" || bad "S1 keymap markers=$k expect 2"
"$PY" -m py_compile "$TMP/fresh.py" >/dev/null 2>&1 \
  && ok "S1 py_compile" || bad "S1 py_compile failed"
grep -q "Cond modmap - User - Caps<->LCtrl full swap" "$TMP/fresh.py" \
  && ok "S1 modmap name present" || bad "S1 modmap name missing"
grep -q "User: Ctrl+Space for IME (fcitx5) passthrough" "$TMP/fresh.py" \
  && ok "S1 keymap name present" || bad "S1 keymap name missing"

echo "== S2: rerun → byte-identical (idempotent) =="
bash "$APPLY" --target "$TMP/fresh.py" --no-fcitx5 --skip-restart >"$TMP/s2.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "S2 exit 0" || bad "S2 exit=$rc (log: $TMP/s2.log)"
cp "$TMP/fresh.py" "$TMP/fresh2.py"
bash "$APPLY" --target "$TMP/fresh2.py" --no-fcitx5 --skip-restart >/dev/null 2>&1
cmp -s "$TMP/fresh.py" "$TMP/fresh2.py" \
  && ok "S2 byte-identical rerun" || bad "S2 rerun changed file"

echo "== S3: hand-patched variant detected → skip, no duplicate =="
cp "$ORACLE" "$TMP/hand.py"
printf '# token-fixture: Cond modmap - User - Caps<->LCtrl full swap (hand variant)\n' >> "$TMP/hand.py"
printf '# token-fixture: User: Ctrl+Space for IME (fcitx5) passthrough (hand variant)\n' >> "$TMP/hand.py"
bash "$APPLY" --target "$TMP/hand.py" --no-fcitx5 --skip-restart >"$TMP/s3.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "S3 exit 0 (already applied)" || bad "S3 exit=$rc (log: $TMP/s3.log)"
$(grep -c "PRESET: hhkb-caps-ctrl (modmap)" "$TMP/hand.py" >/dev/null) \
  && bad "S3 preset blocks inserted onto hand-patched file" \
  || ok "S3 no preset blocks on hand-patched file"
grep -q "already" "$TMP/s3.log" && ok "S3 reports already" || bad "S3 log lacks already-report"

echo "== S4: --dry-run leaves file untouched =="
cp "$ORACLE" "$TMP/dry.py"
bash "$APPLY" --dry-run --target "$TMP/dry.py" --no-fcitx5 --skip-restart >"$TMP/s4.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "S4 exit 0" || bad "S4 exit=$rc (log: $TMP/s4.log)"
cmp -s "$TMP/dry.py" "$TMP/original.py" && ok "S4 untouched" || bad "S4 file changed"

echo "== S5: missing anchor → nonzero + loud message =="
cp "$ORACLE" "$TMP/noanchor.py"
sed -i '/^# \[Global GUI conditional modmaps\] Change modifier keys as in xmodmap$/d' "$TMP/noanchor.py"
cp "$TMP/noanchor.py" "$TMP/noanchor.orig"
grep -qxF '# [Global GUI conditional modmaps] Change modifier keys as in xmodmap' "$TMP/noanchor.orig" \
  && bad "S5 sed deleted both comment levels" || true
bash "$APPLY" --target "$TMP/noanchor.py" --no-fcitx5 --skip-restart >"$TMP/s5.log" 2>&1
rc=$?
[[ $rc -ne 0 ]] && ok "S5 exit nonzero" || bad "S5 exit=0 (should fail)"
grep -qiE "anchor|not found|missing" "$TMP/s5.log" \
  && ok "S5 loud message" || bad "S5 lacks loud message"
cmp -s "$TMP/noanchor.py" "$TMP/noanchor.orig" \
  && ok "S5 no write on failure" || bad "S5 touched file on failure"

echo
echo "results: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
