#!/usr/bin/env bash
# ensures-coverage in vostd's CI (README.md, "在CI中运行").
#
# Run by the workflow ci/ensures-coverage.yml (copied to vostd's
# .github/workflows/) after it has checked out vostd, set up Verus and
# Racket, and checked out this repository.  Everything the check does is
# decided here, so a release of ensures-coverage (main) changes the CI
# without touching vostd; the workflow only prepares the machine.
#
# For the functions a change involves (contrib/pr-functions.rkt), reports
# the outputs their postconditions never mention, in the job summary.
# Advisory only.  When the fixture test fails (tests/run.sh: the VIR of
# this Verus is not what the tool expects) or `check` warns, it stops
# without a report: it exits 1 on pushes (so main shows the tool needs
# fixing) and 0 otherwise.  Any other failure exits 1.
#
# Environment (set by the workflow; defaults for running it by hand):
#   SRC           the vostd checkout (default $GITHUB_WORKSPACE, else .)
#   OUT           output directory (default $RUNNER_TEMP/ensures-coverage)
#   EVENT         github.event_name: pull_request | push | workflow_dispatch
#   PR_BASE       github.event.pull_request.base.sha   (pull_request)
#   PUSH_BEFORE   github.event.before                  (push)
#   INPUT_BASE    the workflow_dispatch input `base`   (default HEAD~1)
#   ITEM_INDEX    a prebuilt item-index; when unset it is built here
#   GITHUB_STEP_SUMMARY  where the summary goes (default $OUT/summary.md)
set -uo pipefail

EC=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(cd "${SRC:-${GITHUB_WORKSPACE:-.}}" && pwd)
OUT=${OUT:-${RUNNER_TEMP:-/tmp}/ensures-coverage}
EVENT=${EVENT:-workflow_dispatch}
mkdir -p "$OUT"
SUMMARY=${GITHUB_STEP_SUMMARY:-$OUT/summary.md}

# What the check covers; decided by the tool, not by vostd's workflow.
RUST_TARGET=x86_64-unknown-none
CRATES=(ostd)
REPORT_LANG=en

VERUS="$SRC/tools/verus/source/target-verus/release/verus"
VERUS_Z3_PATH="$SRC/tools/verus/source/z3"
EC_COMMIT=$(git -C "$EC" rev-parse HEAD 2>/dev/null || echo unknown)
EC_ORIGIN=$(git -C "$EC" config --get remote.origin.url 2>/dev/null | sed -E 's#^https://github.com/##; s#\.git$##')
STOP=""
BASE=""

group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

summary() {
    {
        echo "# ensures-coverage"
        echo
        echo "Advisory only: an output the postcondition never mentions is a signal, not necessarily a defect (see the tool's README)."
        echo
        echo "- Changes: \`${BASE:-?}\`..\`$(git -C "$SRC" rev-parse HEAD)\`, target \`$RUST_TARGET\`, crates \`${CRATES[*]}\`"
        echo "- Verus: \`$("$VERUS" --version 2>/dev/null | sed -n 's/^ *Version: //p')\`, ensures-coverage: \`${EC_ORIGIN:-?}@$EC_COMMIT\`"
        if [[ -n "$STOP" ]]; then
            echo
            echo "**Stopped: $STOP.** No report for this run."
        elif [[ -f "$OUT/pr.md" ]]; then
            echo "- $(head -n 1 "$OUT/check.out")"
            echo "- $(tr '\n' ' ' < "$OUT/select.out")"
            echo
            # GITHUB_STEP_SUMMARY takes at most 1 MiB
            head -c 800000 "$OUT/pr.md"
        else
            echo
            echo "**ensures-coverage did not finish: $1. See the log.**"
        fi
    } >> "$SUMMARY"
}

# an unexpected failure: summary, then exit 1
die() { echo "ensures-coverage: $1" >&2; summary "$1"; exit 1; }

# stopped because the results cannot be trusted
stop() {
    STOP=$1
    echo "ensures-coverage stopped: $STOP" >&2
    summary ""
    [[ $EVENT == push ]] && exit 1
    exit 0
}

# 1. the base commit to diff against
case "$EVENT" in
    pull_request) BASE=${PR_BASE:-} ;;
    push) BASE=${PUSH_BEFORE:-} ;;
    *) BASE=${INPUT_BASE:-} ;;
esac
# a new branch has no `before`
if [[ -z "$BASE" || "$BASE" =~ ^0+$ ]]; then BASE=HEAD~1; fi
BASE=$(git -C "$SRC" rev-parse --verify "$BASE^{commit}") || die "cannot resolve the base commit"
echo "Diffing against $BASE"

# 2. item-index, against the vendored verus_syn (README.md, 准备: without
#    `cargo update` the pinned crates.io version wins)
if [[ -z "${ITEM_INDEX:-}" ]]; then
    group "Build item-index"
    P="patch.crates-io.verus_syn.path=\"$SRC/tools/verus/dependencies/syn\""
    (cd "$EC/item-index" && cargo update -p verus_syn --config "$P" && cargo build --release --config "$P") \
        || die "building item-index failed"
    ITEM_INDEX="$EC/item-index/target/release/item-index"
    endgroup
fi
export ITEM_INDEX

# 3. fixture test
group "Fixture test"
VERUS="$VERUS" VERUS_Z3_PATH="$VERUS_Z3_PATH" "$EC/tests/run.sh" > "$OUT/fixture.txt" 2>&1
status=$?
cat "$OUT/fixture.txt"
endgroup
[[ $status -eq 0 ]] || stop "the fixture test failed: the VIR of this Verus is not what ensures-coverage expects"

# 4. export the VIR of each crate.  cargo-verus writes nothing when it
#    hits its cache (README.md, 运行), hence the check for crate.vir.
VIRS=()
for c in "${CRATES[@]}"; do
    group "Export VIR of $c"
    (cd "$SRC" && cargo dv focus --package "$c" --target "$RUST_TARGET" -- \
        --no-verify --log vir --log-dir "$OUT/vir-$c" 2>&1 | tail -n 20) || die "exporting the VIR of $c failed"
    test -s "$OUT/vir-$c/crate.vir" || die "no crate.vir was written for $c"
    ls -la "$OUT/vir-$c/crate.vir"
    VIRS+=("$OUT/vir-$c/crate.vir")
    endgroup
done

# 5. check every function; any warning means the results cannot be trusted
group "Check"
VIR_LIST=$(IFS=,; echo "${VIRS[*]}")
racket "$EC/main.rkt" check "$VIR_LIST" "$OUT/head.results" "$SRC" "$ITEM_INDEX" \
    2> "$OUT/check.err" | tee "$OUT/check.out" || die "check failed"
cat "$OUT/check.err"
endgroup
[[ -s "$OUT/check.err" ]] && stop "check printed warnings, so its results cannot be trusted"

# 6. the functions the change involves, and the reports
group "Select and report"
racket "$EC/contrib/pr-functions.rkt" "$OUT/head.results" "$SRC" "$BASE" "$OUT/pr.results" \
    | tee "$OUT/select.out" || die "selecting the functions failed"
racket "$EC/main.rkt" report "$OUT/pr.results" "$OUT/pr.md" all --lang "$REPORT_LANG" || die "report failed"
racket "$EC/main.rkt" report "$OUT/head.results" "$OUT/all.md" all --lang "$REPORT_LANG" || die "report failed"
endgroup

summary ""
