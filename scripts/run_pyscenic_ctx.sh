#!/bin/bash
#
# Runs "pyscenic ctx" for each row of a configuration CSV (one TF per row),
# with input/output validation, per-run logging, and a final summary.
#
# Usage:
#   bash scripts/run_pyscenic_ctx.sh [config.csv] [--dry-run] [--force] [--quiet]
#
#   config.csv   path to the CSV (default: artifacts/ctx_runs.local.csv — generate it
#                with scripts/generate_configs.py, don't hand-write it)
#   --dry-run    only validate paths and print the command, without calling pyscenic
#   --force      reprocess runs even if output_path already exists
#   --quiet      don't stream pyscenic's output live, only the log file (good for nohup/cron)
#
# Expected CSV (with header), columns:
#   run_id,tf_name,adj_path,feather_path,tbl_path,loom_path,nes_threshold,mode,num_workers,output_path
#
set -uo pipefail  # no -e: each CSV row is handled individually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_CSV="artifacts/ctx_runs.local.csv"
DRY_RUN=0
FORCE=0
QUIET=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        --quiet) QUIET=1 ;;
        *.csv) CONFIG_CSV="$arg" ;;
        *) log_error "unknown argument: $arg"; exit 2 ;;
    esac
done

if [ ! -f "$CONFIG_CSV" ]; then
    log_error "config file not found: $CONFIG_CSV"
    exit 2
fi

# generate_configs.py writes CSVs into .../<project>/<cell-line>/configs/;
# logs go into .../<project>/<cell-line>/logs/, a sibling of that configs/
# folder (not one global logs/) — so everything about one project/cell-line
# (its configs, its outputs, and what happened when it ran) stays together.
# A CSV that isn't inside a configs/ folder (e.g. artifacts/examples/*.csv,
# the smoke test) falls back to a logs/ folder right next to it instead.
CSV_DIR="$(dirname "$CONFIG_CSV")"
if [ "$(basename "$CSV_DIR")" = "configs" ]; then
    ARTIFACT_DIR="$(dirname "$CSV_DIR")"
else
    ARTIFACT_DIR="$CSV_DIR"
fi
LOGS_DIR="$ARTIFACT_DIR/logs"
mkdir -p "$LOGS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_CSV="$LOGS_DIR/ctx_summary_${TIMESTAMP}.csv"
echo "run_id,tf_name,status,n_regulons,elapsed_seconds,output_size_bytes,num_workers,nes_threshold,mode,started_at,finished_at,log_file" > "$SUMMARY_CSV"

# Total data rows, for the "[i/N]" progress indicator below.
TOTAL_ROWS=$(tail -n +2 "$CONFIG_CSV" | grep -c '[^[:space:]]')

log_info "Using config: $CONFIG_CSV ($TOTAL_ROWS run(s))"
[ "$DRY_RUN" -eq 1 ] && log_warn "--dry-run mode: no pyscenic command will actually be executed."

ANY_FAILED=0
ROW_NUM=0

while IFS=',' read -r run_id tf_name adj_path feather_path tbl_path loom_path nes_threshold mode num_workers output_path || [ -n "$run_id" ]; do
    ROW_NUM=$((ROW_NUM + 1))
    [ "$ROW_NUM" -eq 1 ] && continue  # skip header
    [ -z "$run_id" ] && continue      # skip blank lines

    echo
    log_info "=== [$((ROW_NUM - 1))/$TOTAL_ROWS] [$run_id] Running $tf_name ==="

    LOGFILE="$LOGS_DIR/ctx_${run_id}.log"
    METAFILE="$LOGS_DIR/ctx_${run_id}.meta.json"
    STATUS=""
    NREGULONS=""
    RUN_ELAPSED_SECONDS=0
    RUN_STARTED_AT=""
    RUN_FINISHED_AT=""

    for pair in "adj_path:$adj_path" "feather_path:$feather_path" "tbl_path:$tbl_path" "loom_path:$loom_path"; do
        field="${pair%%:*}"; value="${pair#*:}"
        if [ -z "$STATUS" ] && ! require_file "$value" "[$run_id] $field"; then
            STATUS="FAIL_INPUT"
        fi
    done

    # -s (not just -f): a previous run that crashed mid-write can leave a
    # 0-byte output file, which should be retried, not treated as done.
    if [ -z "$STATUS" ] && [ -s "$output_path" ] && [ "$FORCE" -eq 0 ]; then
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

            write_run_metadata_json "$METAFILE" \
                run_id "$run_id" tf_name "$tf_name" status "$STATUS" command "${CMD[*]}" \
                adj_path "$adj_path" feather_path "$feather_path" tbl_path "$tbl_path" loom_path "$loom_path" \
                num_workers "$num_workers" nes_threshold "$nes_threshold" mode "$mode" output_path "$output_path" \
                n_regulons "${NREGULONS:-0}" output_size_bytes "$(file_size_bytes "$output_path")" \
                started_at "$RUN_STARTED_AT" finished_at "$RUN_FINISHED_AT" \
                elapsed_seconds "$RUN_ELAPSED_SECONDS" hostname "$(hostname)" log_file "$LOGFILE"
        fi
    fi

    if [[ "$STATUS" == FAIL* ]]; then
        ANY_FAILED=1
    fi

    OUTPUT_SIZE=$(file_size_bytes "$output_path")
    echo "$run_id,$tf_name,$STATUS,$NREGULONS,$RUN_ELAPSED_SECONDS,$OUTPUT_SIZE,$num_workers,$nes_threshold,$mode,$RUN_STARTED_AT,$RUN_FINISHED_AT,$LOGFILE" >> "$SUMMARY_CSV"
done < "$CONFIG_CSV"

echo
log_info "Summary saved to: $SUMMARY_CSV"
column -s, -t "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"

if [ "$ANY_FAILED" -eq 1 ]; then
    log_error "One or more runs failed. Check the 'status' column in the summary and the logs in $LOGS_DIR/."
    exit 1
fi

log_ok "All runs processed successfully (or skipped because they already existed)."