# BATS: regression for commit 028d9b7 — 'openemr-cmd worktree list' must not
# abort mid-loop when a state entry's dir has been deleted on disk.
#
# Bug: cmd_worktree_list called wt_validate_dir_safe directly. Under
# 'set -euo pipefail', a non-zero return (deleted dir -> realpath -e fails)
# killed the entire list command before subsequent entries were printed.
# Fix wrapped the call with 'set +e' / 'set -e'. This test guards that
# contract: every branch in .worktrees.json must appear in the output,
# entries whose dir is missing must show status 'missing', exit 0.

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load 'helpers'

setup() {
    SCRIPT="$(oc_script_path)"
    [[ -x "$SCRIPT" ]] || skip "openemr-cmd script not found"

    # Per-test scratch parent so fixed-name subdirs (e.g. 'present-but-incomplete')
    # cannot collide between concurrent test runs.
    TMP_WT_PARENT=$(oc_mktempdir)
    TMP_OPENEMR_ROOT="${TMP_WT_PARENT}/repo"
    mkdir -p "${TMP_OPENEMR_ROOT}"
    STUB_DIR=$(oc_make_docker_stub_dir)

    # OPENEMR_ROOT must be a real git repo: cmd_worktree_list calls
    # 'git -C "${OPENEMR_ROOT}" symbolic-ref --short HEAD' early.
    oc_init_repo "${TMP_OPENEMR_ROOT}"

    # Fixture: two entries, neither dir exists on disk. The buggy code
    # would print the header and then exit on the first iteration; the
    # fixed code prints both rows with status=missing.
    cat > "${TMP_OPENEMR_ROOT}/.worktrees.json" <<JSON
{
  "feature/alpha": {"offset": 1, "dir": "${TMP_WT_PARENT}/does-not-exist-alpha", "env": "easy"},
  "feature/beta":  {"offset": 2, "dir": "${TMP_WT_PARENT}/does-not-exist-beta",  "env": "easy-light"}
}
JSON
}

teardown() {
    # TMP_WT_PARENT now contains TMP_OPENEMR_ROOT plus any fixture subdirs.
    [[ -n "${TMP_WT_PARENT:-}" ]] && rm -rf "${TMP_WT_PARENT}"
    [[ -n "${STUB_DIR:-}" ]]      && rm -rf "${STUB_DIR}"
}

@test "regression(028d9b7): worktree list prints all entries even when a dir is deleted" {
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_OPENEMR_ROOT}" \
        WORKTREE_PARENT="${TMP_WT_PARENT}" \
        "$SCRIPT" worktree list
    assert_success
    assert_output --partial "feature/alpha"
    assert_output --partial "feature/beta"
    assert_output --partial "missing"
}

@test "regression(028d9b7): worktree list shows status 'missing' for the deleted-dir row" {
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_OPENEMR_ROOT}" \
        WORKTREE_PARENT="${TMP_WT_PARENT}" \
        "$SCRIPT" worktree list
    assert_success
    # Each branch row must include 'missing' as its status column.
    # Use grep to confirm both rows independently — assert_output --partial
    # only proves the string appears somewhere.
    echo "$output" | grep -E '^feature/alpha[[:space:]]+easy[[:space:]]+1[[:space:]]+missing[[:space:]]' \
        || fail "expected 'feature/alpha easy 1 missing' row not found in output"
    echo "$output" | grep -E '^feature/beta[[:space:]]+easy-light[[:space:]]+2[[:space:]]+missing[[:space:]]' \
        || fail "expected 'feature/beta easy-light 2 missing' row not found in output"
}

@test "regression(028d9b7): worktree list exits 0 with mixed present+missing entries" {
    # Add a third 'present' entry: dir exists but is NOT a registered git
    # worktree, so wt_validate_dir_safe returns non-zero. The compose-files
    # check fires first (no .env / docker-compose.override.yml), so status
    # is 'missing' regardless. This exercises the loop continuing past
    # multiple non-zero wt_validate_dir_safe returns.
    mkdir -p "${TMP_WT_PARENT}/present-but-incomplete"
    cat > "${TMP_OPENEMR_ROOT}/.worktrees.json" <<JSON
{
  "feature/alpha":   {"offset": 1, "dir": "${TMP_WT_PARENT}/does-not-exist-alpha",  "env": "easy"},
  "feature/present": {"offset": 2, "dir": "${TMP_WT_PARENT}/present-but-incomplete", "env": "easy"},
  "feature/beta":    {"offset": 3, "dir": "${TMP_WT_PARENT}/does-not-exist-beta",   "env": "easy-light"}
}
JSON
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_OPENEMR_ROOT}" \
        WORKTREE_PARENT="${TMP_WT_PARENT}" \
        "$SCRIPT" worktree list
    assert_success
    assert_output --partial "feature/alpha"
    assert_output --partial "feature/present"
    assert_output --partial "feature/beta"
}
