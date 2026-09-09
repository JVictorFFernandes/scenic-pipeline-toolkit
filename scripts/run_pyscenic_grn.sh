#!/bin/bash
#
# Runs "pyscenic grn" for each row of a configuration CSV, with input/output
# validation, per-run logging, and a final summary.
#
# Usage:
#   bash scripts/run_pyscenic_grn.sh [config.csv] [--dry-run] [--force] [--quiet]
#
#   config.csv   path to the CSV (default: artifacts/grn_runs.local.csv — generate it
#                with scripts/generate_configs.py, don't hand-write it)
#   --dry-run    only validate paths and print the command, without calling pyscenic
#   --force      reprocess runs even if output_path already exists
#   --quiet      don't stream pyscenic's output live, only the log file (good for nohup/cron)
#
# Expected CSV (with header), columns:
#   run_id,loom_path,tfs_path,output_path,num_workers,method,seed
#
# 'seed' is optional (leave the column empty for a random seed each run,
# matching pyscenic's own default) — scripts/generate_configs.py always
# fills it in (seed = replicate number) so runs are reproducible.
#
set -uo pipefail  # no -e: each CSV row is handled individually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_CSV="artifacts/grn_runs.local.csv"
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
SUMMARY_CSV="$LOGS_DIR/grn_summary_${TIMESTAMP}.csv"
echo "run_id,status,n_edges,elapsed_seconds,output_size_bytes,num_workers,method,seed,started_at,finished_at,log_file" > "$SUMMARY_CSV"

# Total data rows, for the "[i/N]" progress indicator below.
TOTAL_ROWS=$(tail -n +2 "$CONFIG_CSV" | grep -c '[^[:space:]]')

log_info "Using config: $CONFIG_CSV ($TOTAL_ROWS run(s))"
[ "$DRY_RUN" -eq 1 ] && log_warn "--dry-run mode: no pyscenic command will actually be executed."

ANY_FAILED=0
ROW_NUM=0

# Reading with IFS on a dedicated file descriptor so nothing conflicts with
# anything the pyscenic command might read from stdin.
while IFS=',' read -r run_id loom_path tfs_path output_path num_workers method seed || [ -n "$run_id" ]; do
    ROW_NUM=$((ROW_NUM + 1))
    [ "$ROW_NUM" -eq 1 ] && continue  # skip header
    [ -z "$run_id" ] && continue      # skip blank lines

    echo
    log_info "=== [$((ROW_NUM - 1))/$TOTAL_ROWS] [$run_id] ==="

    LOGFILE="$LOGS_DIR/grn_${run_id}.log"
    METAFILE="$LOGS_DIR/grn_${run_id}.meta.json"
    STATUS=""
    NEDGES=""
    RUN_ELAPSED_SECONDS=0
    RUN_STARTED_AT=""
    RUN_FINISHED_AT=""

    if ! require_file "$loom_path" "[$run_id] loom_path"; then
        STATUS="FAIL_INPUT"
    elif ! require_file "$tfs_path" "[$run_id] tfs_path"; then
        STATUS="FAIL_INPUT"
    fi

    # -s (not just -f): a previous run that crashed mid-write can leave a
    # 0-byte output file, which should be retried, not treated as done.
    if [ -z "$STATUS" ] && [ -s "$output_path" ] && [ "$FORCE" -eq 0 ]; then
        log_warn "[$run_id] output already exists, skipping (use --force to reprocess): $output_path"
        STATUS="SKIPPED"
    fi

    if [ -z "$STATUS" ]; then
        nproc_check "$num_workers"
        mkdir -p "$(dirname "$output_path")"

        CMD=(pyscenic grn --num_workers "$num_workers" --output "$output_path" --method "$method")
        [ -n "$seed" ] && CMD+=(--seed "$seed")
        CMD+=("$loom_path" "$tfs_path")

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

            write_run_metadata_json "$METAFILE" \
                run_id "$run_id" status "$STATUS" command "${CMD[*]}" \
                loom_path "$loom_path" tfs_path "$tfs_path" output_path "$output_path" \
                num_workers "$num_workers" method "$method" seed "$seed" \
                n_edges "${NEDGES:-0}" output_size_bytes "$(file_size_bytes "$output_path")" \
                started_at "$RUN_STARTED_AT" finished_at "$RUN_FINISHED_AT" \
                elapsed_seconds "$RUN_ELAPSED_SECONDS" hostname "$(hostname)" log_file "$LOGFILE"
        fi
    fi

    if [[ "$STATUS" == FAIL* ]]; then
        ANY_FAILED=1
    fi

    OUTPUT_SIZE=$(file_size_bytes "$output_path")
    echo "$run_id,$STATUS,$NEDGES,$RUN_ELAPSED_SECONDS,$OUTPUT_SIZE,$num_workers,$method,$seed,$RUN_STARTED_AT,$RUN_FINISHED_AT,$LOGFILE" >> "$SUMMARY_CSV"
done < "$CONFIG_CSV"

echo
log_info "Summary saved to: $SUMMARY_CSV"
column -s, -t "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"

if [ "$ANY_FAILED" -eq 1 ]; then
    log_error "One or more runs failed. Check the 'status' column in the summary and the logs in $LOGS_DIR/."
    exit 1
fi

log_ok "All runs processed successfully (or skipped because they already existed)."