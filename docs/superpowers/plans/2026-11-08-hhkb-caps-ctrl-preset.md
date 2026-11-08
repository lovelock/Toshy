# HHKB Caps↔Ctrl Preset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an idempotent preset (`presets/hhkb-caps-ctrl/apply.sh` + README) in the `lovelock/Toshy` fork that, on any fresh Toshy install, applies the owner's HHKB-style workflow: full Caps↔LeftCtrl swap, Ctrl+Space passthrough to the IME, and a correct fcitx5 trigger key.

**Architecture:** Single self-contained bash script that performs text-anchored, marker-delimited insertions into `~/.config/toshy/toshy_config.py` (validated by py_compile against Toshy's venv), writes one row of user preferences via Toshy's bundled Python, optionally patches the fcitx5 trigger, and restarts the config service. Idempotency = inserted blocks start/end with preset markers; anchors are exact text lines from the upstream template; every write is preceded by a timestamped backup and hard failure (restore + exit) on any mismatch.

**Tech Stack:** Bash, POSIX text tools (`grep`/`sed`/`awk`), Python via `$HOME/.config/toshy/.venv/bin/python` (for sqlite + py_compile; falls back to `python3`).

**Spec:** `docs/superpowers/specs/2026-11-08-hhkb-caps-ctrl-design.md` (short design doc, committed alongside).

## Global Constraints

- Script is a **single self-contained file** (`apply.sh`); no external assets, so `curl -fsSL <raw-url> | bash` works after a normal upstream Toshy install.
- Anchors are **exact text lines**, never line numbers: (a) active `# [Global GUI conditional modmaps] Change modifier keys as in xmodmap` (the template also has a `# #`-commented copy at an earlier line — must not match that one); (b) the `try:` line whose next line is `    setup_spotlight_input_keymaps(`.
- Insertions carry markers `###  PRESET: hhkb-caps-ctrl (modmap)  ###` and `###  PRESET: hhkb-caps-ctrl (keymap)  ###` (start+end). Presence of a marker = step already applied → skip.
- Detection of the owner's existing hand-applied variant = token `Caps<->LCtrl full swap` (modmap) / `C("LC-Space"):          C("C-Space")` (keymap) → report and skip, do not duplicate.
- Anchor mismatch → loud error, restore backup, exit non-zero. Never partial-write `toshy_config.py`.
- Never touch machine-local settings other than the three named mutations: modmap block, keymap block, `capslock_mode=caps_is_caps` (fcitx5 trigger is opt-in by detection).
- The modmap must be registered **before** the `[Global GUI conditional modmaps]` maps (first-match-wins race with `Key.LEFT_CTRL: Key.LEFT_META`), and the keymap **before** the SPOTL setup call.

## Review Focus

- Template drift: upstream `toshy_config.py` in `default-toshy-config/` is the template oracle; if anchors or tokens are missing the script must fail loudly, not patch blindly. → pinned by Task 2 test step "missing-anchor failure test".
- Double application: running apply.sh twice (or on a hand-patched machine) must never create duplicate blocks. → pinned by Task 2 "idempotency" and "hand-patch detection" steps.
- Syntax breakage: any edit is followed by py_compile; failure restores backup. → pinned by Task 2 "compile check" steps inside tests.
- fcitx5 file variants: `[Hotkey/TriggerKeys]` section may be absent, commented out, or contain multiple entries; replace only when a live `0=` line exists under `[Hotkey/TriggerKeys]`, else print manual hint, never rewrite the file otherwise. → pinned by Task 3 test steps.
- Preferences DB oddities: row missing, table missing, DB locked/absent → use `INSERT OR REPLACE`, create dir if needed, degrade to printed instruction on any sqlite error. → pinned by Task 3 prefs test step.

---

### Task 1: Preset skeleton + insertion engine with markers, anchors and idempotency

**Files:**
- Create: `presets/hhkb-caps-ctrl/apply.sh`
- Create: `presets/hhkb-caps-ctrl/tests/run.sh`
- Test: `presets/hhkb-caps-ctrl/tests/run.sh` (scenarios below)

**Interfaces:**
- Consumes: pristine template oracle at `default-toshy-config/toshy_config.py` inside the repo (test input), or a path given as `--template <file>`.
- Produces: `apply_preset <target_config> <template_config>` function; exit codes 0 = applied/already-applied/nothing-to-do, 1 = hard error; `--dry-run` supported.

The exact block text for both insertions is pinned verbatim in the spec's "Applied blocks" section — copy it verbatim into script heredoc variables (marker-wrapped, TO-REPLACE tokens identical to the hand-applied machine state).

- [ ] **Step 1: Write failing scenario runner**

`tests/run.sh` builds three disposable work files in `mktemp -d`: (a) copy of `default-toshy-config/toshy_config.py` (or `--template` arg), (b) the expected "fresh → applied" assertion: markers exist exactly twice (open+close per block), py_compile via toshy venv python passes; (c) rerun = byte-identical file (`cmp`); (d) `--dry-run` leaves file unreferenced; (e) an anchor-stripped copy → nonzero exit + loud message.

Run: `bash presets/hhkb-caps-ctrl/tests/run.sh`
Expected: FAIL (apply.sh missing / assertions fail)

- [ ] **Step 2: Implement apply.sh insertion engine**

One insertion engine `apply_preset`; two heredoc constants (modmap block, keymap block); anchor lookup via awk line captures with exact-text guards; backup to `<target>.bak-hhkb-%Y%m%d-%H%M%S`; py_compile via `${TOSHY_PYTHON:-$HOME/.config/toshy/.venv/bin/python}` with `python3` fallback; restore+exit 1 on compile fail; token-based skip for the hand-applied variant names `Cond modmap - User - Caps<->LCtrl full swap` and `User: Ctrl+Space for IME (fcitx5) passthrough`.

- [ ] **Step 3: Run scenario tests to green**

Run: `bash presets/hhkb-caps-ctrl/tests/run.sh`
Expected: PASS (fresh-apply, idempotent-replay byte-identical, dry-run untouched, missing-anchor failure, hand-patch detection on a fixture built from the tokens above)

- [ ] **Step 4: Commit**

```bash
git add presets/hhkb-caps-ctrl/apply.sh presets/hhkb-caps-ctrl/tests/run.sh
git commit -m "preset(hhkb-caps-ctrl): idempotent insertion engine with anchors, markers, tests"
```

### Task 2: Preferences, fcitx5 trigger, service restart, flags, summary

**Files:**
- Modify: `presets/hhkb-caps-ctrl/apply.sh`
- Modify: `presets/hhkb-caps-ctrl/tests/run.sh`

**Interfaces:**
- Consumes: Task 1 `apply_preset`.
- Produces: `set_caps_mode_pref`, `apply_fcitx5_trigger`, `restart_toshy_config` functions; CLI flags `--dry-run`, `--no-fcitx5`, `--skip-restart`, `--template <file>`.

- [ ] **Step 1: Add failing prefs/fcitx5 service tests**

Scenario: temp sqlite via venv python (create `config_preferences(name,value)` table with INSERT after UPDATE-check); fcitx5 temp config with `[Hotkey/TriggerKeys]\n0=Caps_Lock\n1=Zenkaku_Hankaku` → expect `0=Control+space`, entries 1,2 untouched; section absent → file untouched + hint printed; `--no-fcitx5` → untouched; dry-run → untouched everywhere; `--skip-restart` skips systemctl call (assert via fake PATH stub).

- [ ] **Step 2: Implement the three functions + flag parsing + final summary block**

caplock_row update = `UPDATE config_preferences SET value='caps_is_caps' WHERE name='capslock_mode'` then `INSERT OR REPLACE` fallback; fcitx5 regex replaces only first `0=` line within `[Hotkey/TriggerKeys]` section; restart = `systemctl --user restart toshy-config.service`, tolerated to fail with notice; summary prints per-item state (applied / already / skipped) + upgrade-rerun reminder + backup paths.

- [ ] **Step 3: Run all tests green**

Run: `bash presets/hhkb-caps-ctrl/tests/run.sh`
Expected: PASS (all prior + new scenarios)

- [ ] **Step 4: Smoke-run `--dry-run` and real run on THIS machine's live install (already hand-patched → expect all-skip report)**

Run: `bash presets/hhkb-caps-ctrl/apply.sh --dry-run` then `bash presets/hhkb-caps-ctrl/apply.sh`
Expected: dry-run shows plan; real run reports every item "already applied", exits 0, live config byte-identical after run.

- [ ] **Step 5: Commit**

```bash
git add presets/hhkb-caps-ctrl/
git commit -m "preset(hhkb-caps-ctrl): prefs, fcitx5 trigger, service restart, flags, summary"
```

### Task 3: README + full-suite pass + push

**Files:**
- Create: `presets/hhkb-caps-ctrl/README.md`
- Create: `docs/superpowers/specs/2026-11-08-hhkb-caps-ctrl-design.md`

**Interfaces:** none (docs only)

- [ ] **Step 1: Write README (中文)**

Sections: 是什么/键位表/全新机器三步走（官方安装→`curl -fsSL https://raw.githubusercontent.com/lovelock/Toshy/preset/hhkb-caps-ctrl/presets/hhkb-caps-ctrl/apply.sh | bash -s --` 或 clone 后 sudo-free 运行）→ 验证清单 → 幂等与升级（Toshy 升级后重跑）→ rc/DE 说明（DE 无关；fcitx5 检测才改；GNOME ibus 无需改）→ 回滚（备份文件路径规律）→ Token 冲突警示（如果上游日后改掉 SPOTL/锚点，脚本会响亮失败而不是乱插）。

- [ ] **Step 2: Self-review pass — run full suite one last time from clean checkout**

Run: `git stash -u && bash presets/hhkb-caps-ctrl/tests/run.sh && git stash pop` 不可行（文件未存在时 stash 语义）; substitute: `git worktree add /tmp/opencode/toshy-verify HEAD && cd /tmp/opencode/toshy-verify && bash presets/hhkb-caps-ctrl/tests/run.sh`
Expected: PASS

- [ ] **Step 3: Push branch**

```bash
git push -u origin preset/hhkb-caps-ctrl
```

Expected: branch on `lovelock/Toshy`, main left tracking upstream default.
