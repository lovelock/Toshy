#!/usr/bin/env bash
# ============================================================================
# Toshy preset: hhkb-caps-ctrl
# ============================================================================
# Applies the owner's HHKB/macOS keyboard workflow to an existing Toshy
# install. DE-agnostic — works anywhere Toshy itself works (KDE/GNOME/Xfce/
# Hyprland/...), the fcitx5 trigger step only runs when fcitx5 is detected.
#
# What it does (idempotent — safe to re-run, e.g. after a Toshy upgrade):
#   1. Inserts a modmap: physical Caps = literal Left Ctrl everywhere,
#      physical Left Ctrl = CapsLock ("full swap").
#   2. Inserts a keymap that re-emits Ctrl+Space unchanged, so the IME
#      (~/.config/fcitx5 trigger = Control+space) keeps working; this
#      outraces Toshy's SPOTL module, which otherwise steals Ctrl+Space
#      for desktop layout switching.
#   3. Sets capslock_mode = caps_is_caps in Toshy preferences.
#   4. (fcitx5 only) fixes the recorded trigger key to Control+space.
#   5. Restarts toshy-config.service.
#
# Flags: --dry-run  --no-fcitx5  --skip-restart
#        --target <file>   (config to patch; default ~/.config/toshy/toshy_config.py)
#        --template <file> (pristine oracle for tests; default: bundled template)
#
# Exit: 0 = applied / already applied; 1 = hard error (no partial writes).
# License: same as the Toshy repository this file ships with.
# ============================================================================
set -euo pipefail

PRESET_NAME="hhkb-caps-ctrl"
MARKER_MOD="###  PRESET: hhkb-caps-ctrl (modmap)  ###"
MARKER_KEY="###  PRESET: hhkb-caps-ctrl (keymap)  ###"
ANCHOR_MODMAP_ACTIVE='# [Global GUI conditional modmaps] Change modifier keys as in xmodmap'
HAND_TOKEN_MODMAP='Caps<->LCtrl full swap'
HAND_TOKEN_KEYMAP='Ctrl+Space for IME'

TARGET_CONFIG="${TOSH_CONFIG:-$HOME/.config/toshy/toshy_config.py}"
TEMPLATE_CONFIG=""   # pristine oracle; used by --template and tests
DRY_RUN=0; NO_FCITX5=0; SKIP_RESTART=0

# --- parse flags ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=1 ;;
        --no-fcitx5)    NO_FCITX5=1 ;;
        --skip-restart) SKIP_RESTART=1 ;;
        --target)       TARGET_CONFIG="$2"; shift ;;
        --template)     TEMPLATE_CONFIG="$2"; shift ;;
        -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# //;s/^#$//;s/^#//' | head -40; exit 0 ;;
        *) echo "hhkb-caps-ctrl: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# --- resolve Toshy python (venv first) --------------------------------------
PYBIN="${TOSHY_PYTHON:-$HOME/.config/toshy/.venv/bin/python}"
[[ -x "$PYBIN" ]] || PYBIN="$(command -v python3)"
if [[ -z "$PYBIN" ]]; then
    echo "hhkb-caps-ctrl: ERROR: no python found (set TOSHY_PYTHON)" >&2; exit 1
fi

log()  { echo "hhkb-caps-ctrl: $*"; }
warn() { echo "hhkb-caps-ctrl: WARNING: $*" >&2; }
die()  { echo "hhkb-caps-ctrl: ERROR: $*" >&2; exit 1; }

[[ -f "$TARGET_CONFIG" ]] || die "target config not found: $TARGET_CONFIG (is Toshy installed?)"
[[ -n "$TEMPLATE_CONFIG" ]] || TEMPLATE_CONFIG="$TARGET_CONFIG"
[[ -f "$TEMPLATE_CONFIG" ]] || die "template not found: $TEMPLATE_CONFIG"

# --- block payloads (matching docs/superpowers/specs/2026-11-08 design) -----
read -r -d '' BLOCK_MODMAP <<'EOF' || true
###  PRESET: hhkb-caps-ctrl (modmap)  ###
# [User custom modmap - preset hhkb-caps-ctrl] Caps <-> Left Ctrl FULL literal swap
# (Mac/Win kbtype). Physical Caps = literal Left Ctrl in every app (GUI + terminals);
# physical Left Ctrl key = CapsLock toggle. Requires capslock_mode='caps_is_caps'.
# Registered BEFORE the base GUI/Terms "Win kbd" modmaps: apply_modmap is
# first-match-wins per inkey (see xwaykeyz transform.py).
modmap("Cond modmap - User - Caps<->LCtrl full swap - Mac/Win kbd", {
    Key.CAPSLOCK:               Key.LEFT_CTRL,                  # Caps is literal Left Ctrl everywhere
    Key.LEFT_CTRL:              Key.CAPSLOCK,                   # Left Ctrl is CapsLock
}, when = lambda ctx:
    cnfg.screen_has_focus and
    (ctx_kbd_is_apple or ctx_kbd_is_windows) and
    not ctx_app_is_remote
)
###  PRESET: hhkb-caps-ctrl (modmap)  ###
EOF

read -r -d '' BLOCK_KEYMAP <<'EOF' || true
###  PRESET: hhkb-caps-ctrl (keymap)  ###
# [User keymap - preset hhkb-caps-ctrl] Free physical Ctrl+Space (Caps + Space)
# for the fcitx5/ibus IME trigger. The SPOTL module below (setup_spotlight_input_keymaps)
# intercepts LC-Space and remaps it to the DE's layout-switching combo (e.g.
# Meta+Alt+L on KDE) in every context, so the Space never reaches apps or the
# input method. This keymap re-emits the combo unchanged -- a true passthrough
# (a None value here would BLOCK the key instead). Registered before the SPOTL
# setup so it wins the first-match-wins race. Cmd+Space (RC-Space -> launcher,
# e.g. KRunner) is intentionally untouched; that mapping lives in SPOTL.
keymap("User: Ctrl+Space for IME (fcitx5) passthrough", {
    C("LC-Space"):          C("C-Space"),           # real Ctrl+Space through to app/IME
    C("Shift-LC-Space"):    C("Shift-C-Space"),     # real Ctrl+Shift+Space through
}, when = lambda ctx:
    cnfg.screen_has_focus and
    not ctx_app_is_remote
)
###  PRESET: hhkb-caps-ctrl (keymap)  ###
EOF

# --- locate anchors (exact-text, in the pristine template if given) ---------
# Both anchors are searched in the PRISTINE template when one is supplied
# (is which case the anchors' exact line text must exist there and in the
# target alike -- the template oracle keeps upgrade drift visible), but the
# insert positions are line numbers from the TARGET.
anchor_modmap_ln() {
    awk -v a="$ANCHOR_MODMAP_ACTIVE" '$0==a{print NR; exit}' "$1"
}
anchor_keymap_ln() {
    awk '$0=="try:"{t=1; tryln=NR; next}
         t && /setup_spotlight_input_keymaps\(/ {print tryln; exit}
         {t=0}' "$1"
}

AM_T="$(anchor_modmap_ln "$TEMPLATE_CONFIG")"
AK_T="$(anchor_keymap_ln "$TEMPLATE_CONFIG")"
AM="$(anchor_modmap_ln "$TARGET_CONFIG")"
AK="$(anchor_keymap_ln "$TARGET_CONFIG")"

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "-- dry run --"
    log "target: $TARGET_CONFIG"
    log "anchor (modmap, active): line ${AM:-MISSING in target}"
    log "anchor (keymap, SPOTL try): line ${AK:-MISSING in target}"
    log "would insert: modmap block ($(echo "$BLOCK_MODMAP" | wc -l) lines) before modmap anchor"
    log "would insert: keymap block ($(echo "$BLOCK_KEYMAP" | wc -l) lines) before keymap anchor"
    log "would set: capslock_mode=caps_is_caps; fcitx5 trigger (if present); service restart"
    log "-- end dry run (nothing written) --"
    exit 0
fi

# --- validity checks BEFORE any writing -------------------------------------
if [[ "$AM_T" == "" || "$AM" == "" ]]; then
    die "anchor '$ANCHOR_MODMAP_ACTIVE' not found (template=${AM_T:-none}, target=${AM:-none}) — template may have changed; do not patch blindly."
fi
if [[ "$AK_T" == "" || "$AK" == "" ]]; then
    die "SPOTL keymap anchor ('try:' + 'setup_spotlight_input_keymaps(' on next line) not found (template=${AK_T:-none}, target=${AK:-none}) — do not patch blindly."
fi

# --- idempotency state ------------------------------------------------------
state_mod="MISSING"; state_key="MISSING"
if grep -qF "$MARKER_MOD" "$TARGET_CONFIG"; then
    state_mod="already (preset markers)"
elif grep -qF "$HAND_TOKEN_MODMAP" "$TARGET_CONFIG"; then
    state_mod="already (hand-applied variant; rerun-safe skip)"
fi
if grep -qF "$MARKER_KEY" "$TARGET_CONFIG"; then
    state_key="already (preset markers)"
elif grep -qF "$HAND_TOKEN_KEYMAP" "$TARGET_CONFIG"; then
    state_key="already (hand-applied variant; rerun-safe skip)"
fi

need_mod=$([[ "$state_mod" == "MISSING" ]] && echo 1 || echo 0)
need_key=$([[ "$state_key" == "MISSING" ]] && echo 1 || echo 0)

BACKUP=""
if [[ $need_mod -ne 0 || $need_key -ne 0 ]]; then
    BACKUP="${TARGET_CONFIG}.bak-${PRESET_NAME}-$(date +%Y%m%d-%H%M%S)"
    cp "$TARGET_CONFIG" "$BACKUP"
fi

W="$TARGET_CONFIG.hkb.tmp.$$"
[[ $need_key -ne 0 ]] && {
    # insert BOTTOM-UP: keymap anchor sits below the modmap anchor; inserting
    # at the lower anchor first would shift the higher anchor's line number.
    head -n $((AK-1)) "$TARGET_CONFIG"     > "$W"
    printf '%s\n' "$BLOCK_KEYMAP"          >> "$W"
    tail -n +"$AK"    "$TARGET_CONFIG"     >> "$W"
    mv "$W" "$TARGET_CONFIG"
    state_key="INSERTED (before SPOTL setup, line $AK)"
}
[[ $need_mod -ne 0 ]] && {
    head -n $((AM-1)) "$TARGET_CONFIG"     > "$W"
    printf '%s\n' "$BLOCK_MODMAP"          >> "$W"
    tail -n +"$AM"    "$TARGET_CONFIG"     >> "$W"
    mv "$W" "$TARGET_CONFIG"
    state_mod="INSERTED (before base GUI modmaps, line $AM)"
}

# --- compile check; restore on any failure -----------------------------------
if [[ $need_mod -ne 0 || $need_key -ne 0 ]]; then
    if ! "$PYBIN" -m py_compile "$TARGET_CONFIG" >/dev/null 2>&1; then
        cp -f "$BACKUP" "$TARGET_CONFIG"
        die "py_compile failed after insertion — config restored from $BACKUP"
    fi
fi

# --- preferences, fcitx5, service (configured in later presets steps) -------
# --- preferences: capslock_mode = caps_is_caps -------------------------------
set_caps_mode_pref() {
    local db="${TOSH_PREFS_DB:-$HOME/.config/toshy/toshy_user_preferences.sqlite}"
    if [[ ! -f "$db" ]]; then
        log "prefs: DB not found at $db — set capslock_mode='caps_is_caps' via the Toshy GUI manually"
        PREFS_STATE="skipped (DB not found)"
        return 0
    fi
    local out
    if ! out=$("$PYBIN" - "$db" <<'PYEOF' 2>&1
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
try:
    cur = con.cursor()
    cur.execute("SELECT value FROM config_preferences WHERE name='capslock_mode'")
    row = cur.fetchone()
    state = row[0] if row else 'absent'
    if state == 'caps_is_caps':
        print("OK already caps_is_caps")
        sys.exit(0)
    cur.execute("UPDATE config_preferences SET value='caps_is_caps' WHERE name='capslock_mode'")
    if cur.rowcount == 0:
        cur.execute("INSERT INTO config_preferences (name, value) VALUES ('capslock_mode','caps_is_caps')")
    con.commit()
    print("OK %s -> caps_is_caps" % state)
except sqlite3.Error as e:
    print("SQLERR %s" % e)
    sys.exit(1)
finally:
    con.close()
PYEOF
    ); then
        log "prefs: FAILED — sqlite says: $out — set capslock_mode='caps_is_caps' via the Toshy GUI"
        PREFS_STATE="skipped (sqlite issue)"
        return 0
    fi
    if [[ "$out" == *SQLERR* || "$out" == *"NOCURSOR"* ]]; then
        log "prefs: SQLITE LIMITATION: ${out#SQLERR } — set capslock_mode='caps_is_caps' via the Toshy GUI"
        PREFS_STATE="skipped (sqlite issue)"
    elif [[ "$out" == *already* ]]; then
        log "prefs: capslock_mode already caps_is_caps"
        PREFS_STATE="already caps_is_caps"
    else
        log "prefs: $out"
        PREFS_STATE="set to caps_is_caps"
    fi
}

# --- fcitx5: recorded trigger key -> Control+space ---------------------------
apply_fcitx5_trigger() {
    if [[ $NO_FCITX5 -eq 1 ]]; then
        log "fcitx5: skipped (--no-fcitx5)"
        FCITX_STATE="skipped (--no-fcitx5)"
        return 0
    fi
    local cfg="${TOSH_FCITX_CONFIG:-$HOME/.config/fcitx5/config}"
    if [[ ! -f "$cfg" ]]; then
        log "fcitx5: not installed ($cfg absent) — Ctrl+Space works out of the box with ibus/GNOME; nothing to do"
        FCITX_STATE="skipped (fcitx5 not present)"
        return 0
    fi
    local b="${cfg}.bak-hhkb-$(date +%Y%m%d-%H%M%S)"
    cp "$cfg" "$b"
    local out
    out=$("$PYBIN" - "$b" "$cfg" <<'PYEOF' 2>&1
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8', errors='replace').read()
# section-scoped: only a live '0=' line inside [Hotkey/TriggerKeys] counts --
# other Hotkey sections (e.g. EnumerateGroupForwardKeys) may legitimately
# carry '0=Control+space' and must not fool the idempotency check.
pat = re.compile(r'\[Hotkey/TriggerKeys\]\n(0=[^\n]*)')
m = pat.search(s)
if not m:
    print("NONE")
elif m.group(1) == '0=Control+space':
    print("ALREADY")
else:
    open(dst, 'w', encoding='utf-8').write(pat.sub('[Hotkey/TriggerKeys]\\n0=Control+space', s, count=1))
    print("OK was '%s'" % m.group(1))
PYEOF
) || { log "fcitx5: patch failed, config untouched (backup kept: $b)"; FCITX_STATE="skipped (patch failed)"; return 0; }
    if [[ "$out" == NONE ]]; then
        rm -f "$b"
        log "fcitx5: [Hotkey/TriggerKeys] with a live '0=' line not found — set TriggerKeys[0]=Control+space manually"
        FCITX_STATE="skipped (section absent; file untouched)"
    elif [[ "$out" == ALREADY ]]; then
        rm -f "$b"
        log "fcitx5: trigger already Control+space"
        FCITX_STATE="already Control+space"
    else
        log "fcitx5: trigger rewritten -> Control+space (was ${out#OK was })  [backup: $b]"
        FCITX_STATE="rewritten to Control+space"
    fi
}

# --- service: restart toshy-config -------------------------------------------
restart_toshy_config() {
    if [[ $SKIP_RESTART -eq 1 ]]; then
        log "service: skipped (--skip-restart)"
        SVC_STATE="skipped (--skip-restart)"
        return 0
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl unavailable — restart Toshy manually to load the changes"
        SVC_STATE="skipped (no systemctl)"
        return 0
    fi
    if systemctl --user restart toshy-config.service 2>/dev/null; then
        log "service: toshy-config restarted"
        SVC_STATE="restarted"
    else
        warn "could not restart toshy-config.service — restart Toshy manually"
        SVC_STATE="failed (manual restart needed)"
    fi
}

# --- run the remaining steps (prefs always idempotent; restart on change) ----
PREFS_STATE="not touched"; FCITX_STATE="not touched"; SVC_STATE="not touched"
set_caps_mode_pref
apply_fcitx5_trigger
if [[ $need_mod -ne 0 || $need_key -ne 0 || "$PREFS_STATE" == "set to caps_is_caps" || "$FCITX_STATE" == "rewritten to Control+space" ]]; then
    restart_toshy_config
else
    SVC_STATE="skipped (nothing changed)"
    log "service: nothing changed — no restart needed"
fi

log "modmap:  $state_mod"
log "keymap:  $state_key"
log "prefs:   $PREFS_STATE"
log "fcitx5:  $FCITX_STATE"
log "service: $SVC_STATE"
[[ -n "$BACKUP" ]] && log "backup:  $BACKUP"
log "upgrades: after a Toshy upgrade, re-run this script — the insertions may be" \
    "regenerated away; the script is idempotent and will restore them."
log "done."
exit 0
