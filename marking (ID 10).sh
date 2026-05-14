#!/bin/bash


FULL_MARKS=${1:-100}
TOTAL_STUDENTS=${2:-5}

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBS_ROOT="$BASE_DIR/Submissions"
EXPECTED="$BASE_DIR/AcceptedOutput.txt"
REPORT="$BASE_DIR/output.csv"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ── Build student list ────────────────────────
build_id_list() {
    local count=$1
    local idx=1
    while [ "$idx" -le "$count" ]; do
        echo "180512${idx}"
        idx=$(( idx + 1 ))
    done
}

mapfile -t ROSTER < <(build_id_list "$TOTAL_STUDENTS")

# ── Run one student script, return line count diff ──
run_and_compare() {
    local uid=$1
    local work_dir="$SUBS_ROOT/$uid"
    local run_file="$SCRATCH/${uid}.out"

    ( cd "$work_dir" && bash "./${uid}.sh" ) >"$run_file" 2>/dev/null

    local bad_lines
    bad_lines=$(diff -w "$EXPECTED" "$run_file" | grep -c '^<')
    echo "$bad_lines"
}

# ── Score one student ─────────────────────────
declare -A earned_score
declare -A exe_path

grade_student() {
    local uid=$1
    local sdir="$SUBS_ROOT/$uid"
    local sfile="$sdir/${uid}.sh"

    if [ ! -d "$sdir" ] || [ ! -f "$sfile" ]; then
        earned_score[$uid]=0
        return
    fi

    local misses
    misses=$(run_and_compare "$uid")
    local penalty=$(( misses * 5 ))
    local raw=$(( FULL_MARKS - penalty ))
    [ "$raw" -lt 0 ] && raw=0

    earned_score[$uid]=$raw
    exe_path[$uid]="$sfile"
}

for student in "${ROSTER[@]}"; do
    grade_student "$student"
done

# ── Plagiarism pass ───────────────────────────
declare -A flagged

total=${#ROSTER[@]}
outer=0
while [ "$outer" -lt "$total" ]; do
    a="${ROSTER[$outer]}"
    [ -z "${exe_path[$a]+x}" ] && { outer=$(( outer + 1 )); continue; }

    inner=$(( outer + 1 ))
    while [ "$inner" -lt "$total" ]; do
        b="${ROSTER[$inner]}"
        [ -z "${exe_path[$b]+x}" ] && { inner=$(( inner + 1 )); continue; }

        result=$(diff -Z -B "${exe_path[$a]}" "${exe_path[$b]}" 2>/dev/null)
        if [ -z "$result" ]; then
            flagged[$a]=true
            flagged[$b]=true
        fi

        inner=$(( inner + 1 ))
    done
    outer=$(( outer + 1 ))
done

# ── Write CSV ─────────────────────────────────
{
    echo "student_id,score"
    for student in "${ROSTER[@]}"; do
        pts=${earned_score[$student]:-0}
        if [ "${flagged[$student]+x}" ]; then
            pts=$(( pts * -1 ))
        fi
        echo "${student},${pts}"
    done
} > "$REPORT"

echo "Done. Report saved to: $REPORT"
