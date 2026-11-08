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
echo "== T1: capslock_mode via prefs DB (temp sqlite) =="
cp "$ORACLE" "$TMP/prefs.py"
"$PY" - "$TMP/prefs.sqlite" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE config_preferences (name TEXT PRIMARY KEY, value TEXT)")
con.execute("INSERT INTO config_preferences VALUES ('capslock_mode','caps_is_esc_and_lctrl_role_swap')")
con.commit(); con.close()
PYEOF
TOSH_PREFS_DB="$TMP/prefs.sqlite" bash "$APPLY" --skip-restart --target "$TMP/prefs.py" >"$TMP/t1.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "T1 exit 0" || bad "T1 exit=$rc (log: $TMP/t1.log)"
v=$("$PY" - "$TMP/prefs.sqlite" <<'PYEOF'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute("SELECT value FROM config_preferences WHERE name='capslock_mode'").fetchone()[0])
PYEOF
)
[[ "$v" == "caps_is_caps" ]] && ok "T1 capslock_mode=caps_is_caps" || bad "T1 value=$v"

echo "== T2: fcitx5 trigger rewritten, other entries intact =="
cp "$ORACLE" "$TMP/fx.py"
mkdir -p "$TMP/fxdir"
printf '[Hotkey/TriggerKeys]\n0=Caps_Lock\n1=Zenkaku_Hankaku\n2=Hangul\n' > "$TMP/fxdir/config"
TOSH_FCITX_CONFIG="$TMP/fxdir/config" bash "$APPLY" --skip-restart --target "$TMP/fx.py" >"$TMP/t2.log" 2>&1
first=$(grep -m1 '^0=' "$TMP/fxdir/config")
[[ "$first" == "0=Control+space" ]] && ok "T2 trigger entry" || bad "T2 trigger=$first"
grep -q '^1=Zenkaku_Hankaku' "$TMP/fxdir/config" && grep -q '^2=Hangul' "$TMP/fxdir/config" \
  && ok "T2 other entries intact" || bad "T2 other entries lost"
ls "$TMP/fxdir"/config.bak-* >/dev/null 2>&1 && ok "T2 backup created" || bad "T2 no backup"

echo "== T3: fcitx5 section absent → untouched + hint =="
rm -rf "$TMP/fxdir2"; mkdir -p "$TMP/fxdir2"
printf '[Behavior]\nPreeditEnabledByDefault=True\n' > "$TMP/fxdir2/config"
cp "$TMP/fxdir2/config" "$TMP/fxdir2/before"
TOSH_FCITX_CONFIG="$TMP/fxdir2/config" bash "$APPLY" --skip-restart --target "$TMP/fx.py" >"$TMP/t3.log" 2>&1
cmp -s "$TMP/fxdir2/config" "$TMP/fxdir2/before" && ok "T3 untouched" || bad "T3 file changed"
grep -qiE "manual|not found" "$TMP/t3.log" && ok "T3 hint printed" || bad "T3 no hint"

echo "== T4: --no-fcitx5 leaves fcitx5 config alone =="
printf '[Hotkey/TriggerKeys]\n0=Caps_Lock\n1=Zenkaku_Hankaku\n2=Hangul\n' > "$TMP/fxdir/config"
TOSH_FCITX_CONFIG="$TMP/fxdir/config" bash "$APPLY" --skip-restart --no-fcitx5 --target "$TMP/fx.py" >"$TMP/t4.log" 2>&1
grep -q '^0=Control+space' "$TMP/fxdir/config" && bad "T4 rewrote trigger despite --no-fcitx5" || ok "T4 skipped"

echo "== T6: fcitx5 already-check must be section-scoped (not file-wide) =="
rm -rf "$TMP/fxdir3"; mkdir -p "$TMP/fxdir3"
cat > "$TMP/fxdir3/config" <<'FCFG'
[Hotkey/EnumerateGroupForwardKeys]
0=Control+space

[Hotkey/TriggerKeys]
0=Caps_Lock
1=Zenkaku_Hankaku
FCFG
TOSH_FCITX_CONFIG="$TMP/fxdir3/config" bash "$APPLY" --skip-restart --target "$TMP/fx.py" >"$TMP/t6.log" 2>&1
first=$(awk '/^\[Hotkey\/TriggerKeys\]/{f=1;next} /^\[/{f=0} f && /^0=/{print; exit}' "$TMP/fxdir3/config")
[[ "$first" == "0=Control+space" ]] && ok "T6 section-scoped rewrite" || bad "T6 trigger stays wrong: $first ($(grep 'fcitx5:' "$TMP/t6.log" | head -1))"

echo "== T7: prefs DB without the table → graceful hint, no crash =="
rm -f "$TMP/notable.sqlite"
"$PY" -c "import sqlite3; sqlite3.connect('$TMP/notable.sqlite').close()"
cp "$ORACLE" "$TMP/hand7.py"
printf '# Cond modmap - User - Caps<->LCtrl full swap (hand variant)\n# User: Ctrl+Space for IME (fcitx5) passthrough\n' >> "$TMP/hand7.py"
TOSH_PREFS_DB="$TMP/notable.sqlite" bash "$APPLY" --skip-restart --target "$TMP/hand7.py" >"$TMP/t7.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "T7 exit 0" || bad "T7 exit=$rc (log: $TMP/t7.log)"
grep -q "caps_is_caps" "$TMP/t7.log" && ok "T7 GUI hint printed" || bad "T7 no hint"

echo "== T8: prefs DB absent → skip + no DB file created =="
rm -f "$TMP/never.sqlite"
cp "$ORACLE" "$TMP/hand8.py"
printf '# Cond modmap - User - Caps<->LCtrl full swap (hand variant)\n# User: Ctrl+Space for IME (fcitx5) passthrough\n' >> "$TMP/hand8.py"
TOSH_PREFS_DB="$TMP/never.sqlite" bash "$APPLY" --skip-restart --target "$TMP/hand8.py" >"$TMP/t8.log" 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "T8 exit 0" || bad "T8 exit=$rc (log: $TMP/t8.log)"
[[ ! -e "$TMP/never.sqlite" ]] && ok "T8 no DB file created" || bad "T8 created a DB file"

echo "== T9: prefs row absent (empty table) → INSERT fallback =="
rm -f "$TMP/empty.sqlite"
"$PY" -c "import sqlite3; con=sqlite3.connect('$TMP/empty.sqlite'); con.execute('CREATE TABLE config_preferences (name TEXT PRIMARY KEY, value TEXT)'); con.commit(); con.close()"
cp "$ORACLE" "$TMP/hand9.py"
printf '# Cond modmap - User - Caps<->LCtrl full swap (hand variant)\n# User: Ctrl+Space for IME (fcitx5) passthrough\n' >> "$TMP/hand9.py"
TOSH_PREFS_DB="$TMP/empty.sqlite" bash "$APPLY" --skip-restart --target "$TMP/hand9.py" >"$TMP/t9.log" 2>&1
v=$("$PY" -c "import sqlite3; print(sqlite3.connect('$TMP/empty.sqlite').execute(\"SELECT value FROM config_preferences WHERE name='capslock_mode'\").fetchone()[0])")
[[ "$v" == "caps_is_caps" ]] && ok "T9 row inserted" || bad "T9 value=$v"


cp "$ORACLE" "$TMP/fresh5.py"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/systemctl" <<STUB
#!/usr/bin/env bash
echo "systemctl called: \$*" >> "$TMP/stubtrace"
exit 0
STUB
chmod +x "$TMP/bin/systemctl"
TOSH_PREFS_DB="$TMP/prefs.sqlite" TOSH_FCITX_CONFIG="$TMP/fxdir/config" \
  PATH="$TMP/bin:$PATH" bash "$APPLY" --skip-restart --target "$TMP/fresh5.py" >"$TMP/t5.log" 2>&1
[[ ! -s "$TMP/stubtrace" ]] && ok "T5a --skip-restart → no systemctl call" || bad "T5a called systemctl despite flag"
cp "$ORACLE" "$TMP/fresh5b.py"
TOSH_PREFS_DB="$TMP/prefs.sqlite" TOSH_FCITX_CONFIG="$TMP/fxdir/config" \
  PATH="$TMP/bin:$PATH" bash "$APPLY" --target "$TMP/fresh5b.py" >"$TMP/t5b.log" 2>&1
[[ -s "$TMP/stubtrace" ]] && ok "T5 systemctl called without --skip-restart" || bad "T5 systemctl not called"
rc=0

echo
echo "results: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
