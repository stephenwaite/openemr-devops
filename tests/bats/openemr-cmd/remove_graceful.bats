# BATS: 'openemr-cmd worktree remove <branch>' graceful path when the
# worktree dir is already gone from disk.
#
# Contract (added in PR #766): when the on-disk dir is missing, skip the
# 'Continue? [y/N]' prompt and the destructive teardown steps; just clean
# up the state entry and emit a hint about leftover docker resources.
# Exit 0.
#
# Rationale: dirs frequently disappear out-of-band (manual rm -rf, IDE
# clean, etc.); failing fast or prompting for confirmation in that case
# blocks the user from clearing state without giving them a useful option.

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load 'helpers'

setup() {
    SCRIPT="$(oc_script_path)"
    [[ -x "$SCRIPT" ]] || skip "openemr-cmd script not found"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    TMP_WT_PARENT=$(oc_mktempdir)
    TMP_OPENEMR_ROOT="${TMP_WT_PARENT}/repo"
    mkdir -p "${TMP_OPENEMR_ROOT}"
    STUB_DIR=$(oc_make_docker_stub_dir)
    STATE_FILE="${TMP_OPENEMR_ROOT}/.worktrees.json"

    oc_init_repo "${TMP_OPENEMR_ROOT}"
}

teardown() {
    [[ -n "${TMP_WT_PARENT:-}" ]] && rm -rf "${TMP_WT_PARENT}"
    [[ -n "${STUB_DIR:-}" ]]      && rm -rf "${STUB_DIR}"
}

@test "remove <branch> when dir is gone: no prompt, exit 0, prints docker-cleanup hint, state entry removed" {
    # State entry whose dir is intentionally not created on disk.
    cat > "${STATE_FILE}" <<JSON
{
  "feature/gone": {"offset": 1, "dir": "${TMP_WT_PARENT}/does-not-exist", "env": "easy"}
}
JSON

    # No stdin redirection: the graceful path skips `read -rp` entirely.
    # If it ever regressed and prompted again, this run would block
    # forever (BATS would kill it on timeout). The fast pass IS the
    # "no prompt" assertion.
    run env \
        PATH="${STUB_DIR}:$PATH" \
        OPENEMR_ROOT="${TMP_OPENEMR_ROOT}" \
        WORKTREE_PARENT="${TMP_WT_PARENT}" \
        "$SCRIPT" worktree remove feature/gone
    assert_success

    # The graceful-path 'wt_info' messages must be present.
    assert_output --partial "Worktree dir was already gone"
    # Docker-cleanup hint uses the slugified branch name. wt_slug
    # turns 'feature/gone' into 'feature-gone'.
    assert_output --partial "docker compose -p openemr-feature-gone down -v"
    # And we must NOT have seen the destructive-path prompt.
    refute_output --partial "Continue? [y/N]"

    # State entry actually removed.
    run jq -r 'has("feature/gone")' "${STATE_FILE}"
    assert_success
    assert_output "false"
}
