#!/bin/bash
#
# Runs "pyscenic grn" for each row of a configuration CSV, with input/output
# validation, per-run logging, and a final summary.
#
# Usage:
#   bash scripts/run_pyscenic_grn.sh [config.csv] [--dry-run] [--force]
#
#   config.csv   path to the CSV (default: configs/grn_runs.csv)
#   --dry-run    only validate paths and print the command, without calling pyscenic
#   --force      reprocess runs even if output_path already exists
#
# Expected CSV (with header), columns:
#   run_id,loom_path,tfs_path,output_path,num_workers,method
#
set -uo pipefail  # no -e: each CSV row is handled individually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_CSV="configs/grn_runs.csv"
DRY_RUN=0
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        *.csv) CONFIG_CSV="$arg" ;;
        *) log_error "unknown argument: $arg"; exit 2 ;;
    esac
done

if [ ! -f "$CONFIG_CSV" ]; then
    log_error "config file not found: $CONFIG_CSV"
    exit 2
fi

mkdir -p logs outs

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_CSV="logs/grn_summary_${TIMESTAMP}.csv"
echo "run_id,status,n_edges,elapsed_seconds,log_file" > "$SUMMARY_CSV"

log_info "Using config: $CONFIG_CSV"
[ "$DRY_RUN" -eq 1 ] && log_warn "--dry-run mode: no pyscenic command will actually be executed."

ANY_FAILED=0
ROW_NUM=0

# Reading with IFS on a dedicated file descriptor so nothing conflicts with
# anything the pyscenic command might read from stdin.
while IFS=',' read -r run_id loom_path tfs_path output_path num_workers method || [ -n "$run_id" ]; do
    ROW_NUM=$((ROW_NUM + 1))
    [ "$ROW_NUM" -eq 1 ] && continue  # skip header
    [ -z "$run_id" ] && continue      # skip blank lines

    echo
    log_info "=== [$run_id] ==="

    LOGFILE="logs/grn_${run_id}.log"
    STATUS=""
    NEDGES=""
    RUN_ELAPSED_SECONDS=0

    if ! require_file "$loom_path" "[$run_id] loom_path"; then
        STATUS="FAIL_INPUT"
    elif ! require_file "$tfs_path" "[$run_id] tfs_path"; then
        STATUS="FAIL_INPUT"
    fi

    if [ -z "$STATUS" ] && [ -f "$output_path" ] && [ "$FORCE" -eq 0 ]; then
        log_warn "[$run_id] output already exists, skipping (use --force to reprocess): $output_path"
        STATUS="SKIPPED"
    fi

    if [ -z "$STATUS" ]; then
        nproc_check "$num_workers"
        mkdir -p "$(dirname "$output_path")"

        CMD=(pyscenic grn --num_workers "$num_workers" --output "$output_path" --method "$method" "$loom_path" "$tfs_path")

        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[$run_id] (dry-run) command: ${CMD[*]}"
            STATUS="DRY_RUN"
        else
            log_info "[$run_id] running: ${CMD[*]}"
            if run_and_log "$LOGFILE" -- "${CMD[@]}"; then
                if validate_csv_output "$output_path" "TF" "target" "importance"; then
                    STATUS="OK"
                    NEDGES="$VALIDATE_NROWS"
                    log_ok "[$run_id] finished in ${RUN_ELAPSED_SECONDS}s, $NEDGES edges generated"
                else
                    STATUS="FAIL_OUTPUT"
                fi
            else
                STATUS="FAIL_RUN"
                log_error "[$run_id] 'pyscenic grn' exited with an error, see $LOGFILE"
            fi
        fi
    fi

    if [[ "$STATUS" == FAIL* ]]; then
        ANY_FAILED=1
    fi

    echo "$run_id,$STATUS,$NEDGES,$RUN_ELAPSED_SECONDS,$LOGFILE" >> "$SUMMARY_CSV"
done < "$CONFIG_CSV"

echo
log_info "Summary saved to: $SUMMARY_CSV"
column -s, -t "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"

if [ "$ANY_FAILED" -eq 1 ]; then
    log_error "One or more runs failed. Check the 'status' column in the summary and the logs in logs/."
    exit 1
fi

log_ok "All runs processed successfully (or skipped because they already existed)."