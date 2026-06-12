# BATS: 'openemr-cmd worktree prune' — state-entry hygiene for stale rows.
#
# Contract covered:
#   - empty state (file missing OR '{}') prints '(no stale entries)' and exits 0
#   - a state entry whose dir is gone from disk is pruned
#   - a 'partial' entry (dir intact + registered as git worktree, but compose
#     files missing) is NOT pruned — it is regen-able, not prunable. This is
#     the key correctness contract of the missing/partial split.
#   - --dry-run announces would-be prunes without mutating the state file
#   - mixed populations prune ONLY the stale row, leaving partial + valid
#     entries intact

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load 'helpers'

setup() {
    SCRIPT="$(oc_script_path)"
    [[ -x "$SCRIPT" ]] || skip "openemr-cmd script not found"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    # Per-test scratch parent — avoids cross-test races on fixed-name
    # subdirs under a shared /tmp parent (see PR #765 fix to the
    # regression file).
    TMP_WT_PARENT=$(oc_mktempdir)
    TMP_OPENEMR_ROOT="${TMP_WT_PARENT}/repo"
    mkdir -p "${TMP_OPENEMR_ROOT}"
    STUB_DIR=$(oc_make_docker_stub_dir)
    STATE_FILE="${TMP_OPENEMR_ROOT}/.worktrees.json"

    # OPENEMR_ROOT must be a real git repo: cmd_worktree_prune calls
    # 'git -C "${OPENEMR_ROOT}" worktree list --porcelain' via
    # wt_validate_dir_safe.
    oc_init_repo "${TMP_OPENEMR_ROOT}"
}

teardown() {
    [[ -n "${TMP_WT_PARENT:-}" ]] && rm -rf "${TMP_WT_PARENT}"
    [[ -n "${STUB_DIR:-}" ]]      && rm -rf "${STUB_DIR}"
}

# Convenience runner — fills in all env vars the script needs.
oc_run_prune() {
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_OPENEMR_ROOT}" \
        WORKTREE_PARENT="${TMP_WT_PARENT}" \
        "$SCRIPT" worktree prune "$@"
}

# --- empty cases -------------------------------------------------------------

@test "prune with no .worktrees.json present prints '(no stale entries)' and exits 0" {
    # wt_init_state will create an empty {} file, then the empty branch fires.
    rm -f "${STATE_FILE}"
    oc_run_prune
    assert_success
    assert_output --partial "(no stale entries)"
}

@test "prune with empty state object '{}' prints '(no stale entries)' and exits 0" {
    echo '{}' > "${STATE_FILE}"
    oc_run_prune
    assert_success
    assert_output --partial "(no stale entries)"
}

# --- single stale entry ------------------------------------------------------

@test "prune removes a single stale entry (dir missing on disk)" {
    cat > "${STATE_FILE}" <<JSON
{
  "feature/stale": {"offset": 1, "dir": "${TMP_WT_PARENT}/does-not-exist", "env": "easy"}
}
JSON
    oc_run_prune
    assert_success
    assert_output --partial "Pruned stale entry: 'feature/stale'"
    assert_output --partial "Pruned 1 stale worktree entries."
    # The entry must actually be gone from the state file.
    run jq -r 'has("feature/stale")' "${STATE_FILE}"
    assert_success
    assert_output "false"
}

# --- the key correctness test -----------------------------------------------

@test "prune does NOT remove a partial entry (dir intact + registered, compose files missing)" {
    # Register a real git worktree under WORKTREE_PARENT. This makes
    # wt_validate_dir_safe pass: the dir exists, is inside WORKTREE_PARENT,
    # and shows up in `git worktree list --porcelain`. We deliberately do
    # NOT create the docker/development-easy/* compose files — that is
    # the 'partial' state.
    local wt_dir
    wt_dir=$(oc_add_registered_worktree "${TMP_OPENEMR_ROOT}" "${TMP_WT_PARENT}" "feature/partial")
    cat > "${STATE_FILE}" <<JSON
{
  "feature/partial": {"offset": 1, "dir": "${wt_dir}", "env": "easy"}
}
JSON
    # Snapshot the state file before invocation so we can assert it is
    # byte-identical afterwards.
    local before
    before=$(cat "${STATE_FILE}")

    oc_run_prune
    assert_success
    assert_output --partial "(no stale entries)"

    # State file unchanged.
    [[ "$(cat "${STATE_FILE}")" = "${before}" ]] \
        || fail "state file mutated by prune of a partial entry"
    # The entry must still be present.
    run jq -r 'has("feature/partial")' "${STATE_FILE}"
    assert_success
    assert_output "true"
}

# --- --dry-run --------------------------------------------------------------

@test "prune --dry-run announces would-be prunes without mutating state" {
    cat > "${STATE_FILE}" <<JSON
{
  "feature/stale": {"offset": 1, "dir": "${TMP_WT_PARENT}/does-not-exist", "env": "easy"}
}
JSON
    local before
    before=$(cat "${STATE_FILE}")

    oc_run_prune --dry-run
    assert_success
    assert_output --partial "Would prune stale entry:"
    assert_output --partial "Would prune 1 stale worktree entries."

    # State file unchanged.
    [[ "$(cat "${STATE_FILE}")" = "${before}" ]] \
        || fail "state file mutated by --dry-run prune"
    run jq -r 'has("feature/stale")' "${STATE_FILE}"
    assert_success
    assert_output "true"
}

# --- mixed populations ------------------------------------------------------

@test "prune mixed: one stale + one partial + one valid → only the stale entry removed" {
    # Two registered worktrees: one we leave bare (partial), one we'll
    # fully populate with compose files (valid). Plus one entry pointing
    # at a nonexistent dir (stale).
    local wt_partial wt_valid
    wt_partial=$(oc_add_registered_worktree "${TMP_OPENEMR_ROOT}" "${TMP_WT_PARENT}" "feature/partial")
    wt_valid=$(oc_add_registered_worktree   "${TMP_OPENEMR_ROOT}" "${TMP_WT_PARENT}" "feature/valid")
    # Populate the valid one's compose files so list would show status
    # other than 'partial'. prune doesn't actually care about these files
    # (only wt_validate_dir_safe), but populating them keeps the fixture
    # honest about what 'valid' means.
    mkdir -p "${wt_valid}/docker/development-easy"
    : > "${wt_valid}/docker/development-easy/.env"
    : > "${wt_valid}/docker/development-easy/docker-compose.override.yml"

    cat > "${STATE_FILE}" <<JSON
{
  "feature/stale":   {"offset": 1, "dir": "${TMP_WT_PARENT}/gone",   "env": "easy"},
  "feature/partial": {"offset": 2, "dir": "${wt_partial}",           "env": "easy"},
  "feature/valid":   {"offset": 3, "dir": "${wt_valid}",             "env": "easy"}
}
JSON

    oc_run_prune
    assert_success
    assert_output --partial "Pruned stale entry: 'feature/stale'"
    assert_output --partial "Pruned 1 stale worktree entries."

    # Only the stale entry should be gone.
    run jq -r 'has("feature/stale")' "${STATE_FILE}"
    assert_success
    assert_output "false"
    run jq -r 'has("feature/partial")' "${STATE_FILE}"
    assert_success
    assert_output "true"
    run jq -r 'has("feature/valid")' "${STATE_FILE}"
    assert_success
    assert_output "true"
}
