# BATS: openemr-cmd CLI smoke tests — top-level argument handling.
# These tests invoke the script as a subprocess (real CLI surface) rather
# than sourcing it, so they catch regressions in dispatch and exit codes.

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load 'helpers'

setup() {
    SCRIPT="$(oc_script_path)"
    [[ -x "$SCRIPT" ]] || skip "openemr-cmd script not found"
    TMP_ROOT=$(oc_mktempdir)
    STUB_DIR=$(oc_make_docker_stub_dir)
    # Init a real repo so worktree subcommands' git calls succeed.
    oc_init_repo "${TMP_ROOT}"
}

teardown() {
    [[ -n "${TMP_ROOT:-}" ]]  && rm -rf "${TMP_ROOT}"
    [[ -n "${STUB_DIR:-}" ]] && rm -rf "${STUB_DIR}"
}

# --- --version ---------------------------------------------------------------

@test "openemr-cmd --version prints VERSION and exits 14 (VERSION_EXIT_CODE)" {
    # The script defines VERSION_EXIT_CODE=14 and exits with it after
    # printing 'openemr-cmd <VERSION>'. We assert the printed string
    # matches the VERSION= line in the script, so this test self-updates
    # as VERSION bumps.
    expected=$(grep -E '^VERSION=' "$SCRIPT" | head -1 | sed -E 's/^VERSION="([^"]+)".*/\1/')
    [[ -n "$expected" ]]
    run env PATH="${STUB_DIR}:$PATH" "$SCRIPT" --version
    assert_output "openemr-cmd ${expected}"
    [[ "$status" -eq 14 ]]
}

@test "openemr-cmd -v is equivalent to --version" {
    expected=$(grep -E '^VERSION=' "$SCRIPT" | head -1 | sed -E 's/^VERSION="([^"]+)".*/\1/')
    run env PATH="${STUB_DIR}:$PATH" "$SCRIPT" -v
    assert_output "openemr-cmd ${expected}"
    [[ "$status" -eq 14 ]]
}

# --- worktree subcommand dispatch -------------------------------------------

@test "openemr-cmd worktree (no subcommand) prints usage and exits non-zero" {
    run env \
        OPENEMR_ROOT="${TMP_ROOT}" \
        WORKTREE_PARENT="$(dirname "${TMP_ROOT}")" \
        "$SCRIPT" worktree
    assert_output --partial "Usage: openemr-cmd worktree"
    [[ "$status" -ne 0 ]]
}

@test "openemr-cmd wt (alias, no subcommand) prints usage and exits non-zero" {
    run env \
        OPENEMR_ROOT="${TMP_ROOT}" \
        WORKTREE_PARENT="$(dirname "${TMP_ROOT}")" \
        "$SCRIPT" wt
    assert_output --partial "Usage: openemr-cmd worktree"
    [[ "$status" -ne 0 ]]
}

# --- worktree list empty cases ---------------------------------------------

@test "openemr-cmd worktree list with no .worktrees.json prints '(no worktrees)' and exits 0" {
    # Ensure no state file is present.
    rm -f "${TMP_ROOT}/.worktrees.json"
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_ROOT}" \
        WORKTREE_PARENT="$(dirname "${TMP_ROOT}")" \
        "$SCRIPT" worktree list
    # cmd_worktree_list calls wt_init_state which CREATES an empty {} file
    # if missing, then the empty-{} branch kicks in. Either way exit 0 and
    # the '(no worktrees)' line must appear.
    assert_success
    assert_output --partial "(no worktrees)"
}

@test "openemr-cmd worktree list with {} state prints '(no worktrees)' and exits 0" {
    echo '{}' > "${TMP_ROOT}/.worktrees.json"
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_ROOT}" \
        WORKTREE_PARENT="$(dirname "${TMP_ROOT}")" \
        "$SCRIPT" worktree list
    assert_success
    assert_output --partial "(no worktrees)"
}
