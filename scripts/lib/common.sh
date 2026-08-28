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

# run_and_log <log_file> -- <command...>
# Runs the command, saves stdout+stderr to the log file, and returns the
# command's exit code (deliberately not using 'set -e' here — the caller
# decides what to do on failure).
run_and_log() {
    local logfile="$1"; shift
    if [ "$1" == "--" ]; then shift; fi
    local start_ts end_ts
    start_ts=$(date +%s)
    "$@" > "$logfile" 2>&1
    local rc=$?
    end_ts=$(date +%s)
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