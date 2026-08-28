#!/bin/bash
#
# Runs "pyscenic ctx" for each row of a configuration CSV (one TF per row),
# with input/output validation, per-run logging, and a final summary.
#
# Usage:
#   bash scripts/run_pyscenic_ctx.sh [config.csv] [--dry-run] [--force]
#
#   config.csv   path to the CSV (default: configs/ctx_runs.csv)
#   --dry-run    only validate paths and print the command, without calling pyscenic
#   --force      reprocess runs even if output_path already exists
#
# Expected CSV (with header), columns:
#   run_id,tf_name,adj_path,feather_path,tbl_path,loom_path,nes_threshold,mode,num_workers,output_path
#
set -uo pipefail  # no -e: each CSV row is handled individually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_CSV="configs/ctx_runs.csv"
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

mkdir -p logs

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_CSV="logs/ctx_summary_${TIMESTAMP}.csv"
echo "run_id,tf_name,status,n_regulons,elapsed_seconds,log_file" > "$SUMMARY_CSV"

log_info "Using config: $CONFIG_CSV"
[ "$DRY_RUN" -eq 1 ] && log_warn "--dry-run mode: no pyscenic command will actually be executed."

ANY_FAILED=0
ROW_NUM=0

while IFS=',' read -r run_id tf_name adj_path feather_path tbl_path loom_path nes_threshold mode num_workers output_path || [ -n "$run_id" ]; do
    ROW_NUM=$((ROW_NUM + 1))
    [ "$ROW_NUM" -eq 1 ] && continue  # skip header
    [ -z "$run_id" ] && continue      # skip blank lines

    echo
    log_info "=== [$run_id] Running $tf_name ==="

    LOGFILE="logs/ctx_${run_id}.log"
    STATUS=""
    NREGULONS=""
    RUN_ELAPSED_SECONDS=0

    for pair in "adj_path:$adj_path" "feather_path:$feather_path" "tbl_path:$tbl_path" "loom_path:$loom_path"; do
        field="${pair%%:*}"; value="${pair#*:}"
        if [ -z "$STATUS" ] && ! require_file "$value" "[$run_id] $field"; then
            STATUS="FAIL_INPUT"
        fi
    done

    if [ -z "$STATUS" ] && [ -f "$output_path" ] && [ "$FORCE" -eq 0 ]; then
        log_warn "[$run_id] output already exists, skipping (use --force to reprocess): $output_path"
        STATUS="SKIPPED"
    fi

    if [ -z "$STATUS" ]; then
        nproc_check "$num_workers"
        mkdir -p "$(dirname "$output_path")"

        CMD=(pyscenic ctx "$adj_path" "$feather_path"
             --annotations_fname "$tbl_path"
             --expression_mtx_fname "$loom_path"
             --nes_threshold "$nes_threshold"
             --mode "$mode"
             --output "$output_path"
             --num_workers "$num_workers"
             --mask_dropouts)

        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[$run_id] (dry-run) command: ${CMD[*]}"
            STATUS="DRY_RUN"
        else
            log_info "[$run_id] running: ${CMD[*]}"
            if run_and_log "$LOGFILE" -- "${CMD[@]}"; then
                if validate_csv_output "$output_path" "TF" "MotifID" "AUC"; then
                    STATUS="OK"
                    NREGULONS="$VALIDATE_NROWS"
                    log_ok "[$run_id] finished in ${RUN_ELAPSED_SECONDS}s, $NREGULONS rows generated"
                else
                    STATUS="FAIL_OUTPUT"
                fi
            else
                STATUS="FAIL_RUN"
                log_error "[$run_id] 'pyscenic ctx' exited with an error, see $LOGFILE"
            fi
        fi
    fi

    if [[ "$STATUS" == FAIL* ]]; then
        ANY_FAILED=1
    fi

    echo "$run_id,$tf_name,$STATUS,$NREGULONS,$RUN_ELAPSED_SECONDS,$LOGFILE" >> "$SUMMARY_CSV"
done < "$CONFIG_CSV"

echo
log_info "Summary saved to: $SUMMARY_CSV"
column -s, -t "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"

if [ "$ANY_FAILED" -eq 1 ]; then
    log_error "One or more runs failed. Check the 'status' column in the summary and the logs in logs/."
    exit 1
fi

log_ok "All runs processed successfully (or skipped because they already existed)."