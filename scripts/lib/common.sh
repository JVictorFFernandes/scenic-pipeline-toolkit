#!/bin/bash
# Shared logging and validation functions for the run_pyscenic_*.sh scripts.
# This file is meant to be sourced, not executed directly.

# Colors (automatically disabled when output isn't a terminal)
if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_RESET='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

log_info()  { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
log_ok()    { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_error() { echo -e "${C_RED}[FAIL]${C_RESET} $*" >&2; }

# require_file <path> <description>
# Returns 1 (without aborting the script) if the file doesn't exist or is empty.
require_file() {
    local path="$1" desc="$2"
    if [ -z "$path" ]; then
        log_error "$desc: empty path in CSV"
        return 1
    fi
    if [ ! -f "$path" ]; then
        log_error "$desc not found: $path"
        return 1
    fi
    if [ ! -s "$path" ]; then
        log_error "$desc is empty (0 bytes): $path"
        return 1
    fi
    return 0
}

# validate_csv_output <path> <col1> [col2 ...]
# Checks that the output file exists, isn't empty, and contains the expected
# columns in the header (substring match, order not required).
# Returns the number of data rows (excluding header) via the global variable
# VALIDATE_NROWS.
validate_csv_output() {
    local path="$1"; shift
    local expected_cols=("$@")

    if [ ! -f "$path" ]; then
        log_error "output was not created: $path"
        return 1
    fi
    if [ ! -s "$path" ]; then
        log_error "output is empty (0 bytes): $path"
        return 1
    fi

    # pyscenic ctx writes a multi-line header (pandas MultiIndex), so we
    # search the first few lines instead of just the first one.
    local header
    header=$(head -n 3 "$path")
    local col
    for col in "${expected_cols[@]}"; do
        if [[ "$header" != *"$col"* ]]; then
            log_error "expected column '$col' not found at the start of $path"
            return 1
        fi
    done

    VALIDATE_NROWS=$(( $(wc -l < "$path") - 1 ))
    if [ "$VALIDATE_NROWS" -le 0 ]; then
        log_error "output has no data rows: $path"
        return 1
    fi
    return 0
}

# Lines matched here are dropped from the LIVE terminal stream only — the
# full, unfiltered output always still goes to the log file. These are
# warnings that pyscenic/ctxcore print identically on every single run
# (dependency deprecation notices, a static note about correlation
# calculation) and add nothing after you've seen them once, but get very
# repetitive across many rows in a CSV.
NOISY_LIVE_PATTERN='pkg_resources is deprecated|from pkg_resources import|Note on correlation calculation|Previously, the default was to calculate|current default is now to use all cells|The original settings can be retained|Dropout masking is currently set to'

# run_and_log <log_file> -- <command...>
# Runs the command, saving stdout+stderr to the log file. By default also
# streams live to the terminal (filtering out NOISY_LIVE_PATTERN from what's
# shown live, not from the log file), and returns the command's exit code
# (deliberately not using 'set -e' here — the caller decides what to do on
# failure).
#
# Streaming live matters here: with --mode dask_multiprocessing, "pyscenic
# ctx" already prints a real percentage progress bar (dask.diagnostics.
# ProgressBar) to stdout, and "pyscenic grn" prints milestone messages
# ("Loading expression matrix.", "Inferring regulatory networks.", ...) —
# both were previously hidden until the run finished because output went
# only to the log file.
#
# Set QUIET=1 (see --quiet in the calling scripts) to go back to the old
# behavior: no live output at all, only the log file — useful for
# unattended runs (nohup/cron) where nobody is watching the terminal.
run_and_log() {
    local logfile="$1"; shift
    if [ "$1" == "--" ]; then shift; fi
    local start_ts end_ts
    RUN_STARTED_AT=$(date -Iseconds)
    start_ts=$(date +%s)
    if [ "${QUIET:-0}" -eq 1 ]; then
        "$@" > "$logfile" 2>&1
        local rc=$?
    else
        "$@" 2>&1 | tee "$logfile" | grep -Ev "$NOISY_LIVE_PATTERN"
        local rc=${PIPESTATUS[0]}
    fi
    end_ts=$(date +%s)
    RUN_FINISHED_AT=$(date -Iseconds)
    RUN_ELAPSED_SECONDS=$(( end_ts - start_ts ))
    return $rc
}

# nproc_check <num_workers>
# Only warns (doesn't block) if num_workers exceeds the cores available.
nproc_check() {
    local requested="$1"
    local available
    available=$(nproc 2>/dev/null || echo "?")
    if [ "$available" != "?" ] && [ "$requested" -gt "$available" ]; then
        log_warn "num_workers=$requested is higher than the $available cores available on this machine"
    fi
}

# file_size_bytes <path>
# Prints the file size in bytes, or 0 if the file doesn't exist. Used for
# the lightweight telemetry in the summary CSVs and per-run metadata JSON.
file_size_bytes() {
    local path="$1"
    if [ -f "$path" ]; then
        stat -c%s "$path" 2>/dev/null || wc -c < "$path"
    else
        echo 0
    fi
}

# json_escape <string>
# Minimal JSON string escaping (backslashes and double quotes — enough for
# the paths/hostnames/commands we actually put in the metadata files).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# write_run_metadata_json <json_path> <key1> <value1> [<key2> <value2> ...]
# Writes a small JSON object of run metadata (parameters, timestamps,
# output size, etc.) next to the log file, for later programmatic analysis
# (e.g. aggregating stats across many replicates). Numeric-looking values
# are written unquoted; everything else is quoted and escaped.
write_run_metadata_json() {
    local json_path="$1"; shift
    local out="{" first=1
    while [ "$#" -ge 2 ]; do
        local key="$1" value="$2"; shift 2
        [ "$first" -eq 1 ] && first=0 || out+=","
        if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            out+="\"$key\":$value"
        else
            out+="\"$key\":\"$(json_escape "$value")\""
        fi
    done
    out+="}"
    printf '%s\n' "$out" > "$json_path"
}