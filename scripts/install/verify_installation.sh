#!/bin/bash
#
# Smoke test for the installation done by install_pyscenic_pycistarget.sh.
# Run this after installation to confirm everything is fine before
# launching real runs. Doesn't use 'set -e': we want to run ALL checks and
# show a final summary, even if one of them fails.
#
# pyscenic and pycistarget live in SEPARATE conda environments (see the
# comment at the top of install_pyscenic_pycistarget.sh about the pandas
# conflict).
#
# Usage:
#   bash scripts/install/verify_installation.sh
#
ENV_PYSCENIC="scenic"
ENV_PYCISTARGET="pycistarget"
FAILED=0

pass() { echo "[ OK ] $*"; }
fail() { echo "[FAIL] $*"; FAILED=1; }

echo "=== Verifying installation ==="

# 0) conda available
# If the current terminal was opened before 'conda init' ran (or you didn't
# reopen the terminal after installation), 'conda' might not be on PATH yet
# even though it's installed. Try to find it in the usual locations before
# giving up.
if ! command -v conda >/dev/null 2>&1; then
    for candidate in "$HOME/miniforge3" "$HOME/miniconda3" "$HOME/anaconda3" "/opt/conda"; do
        if [ -f "$candidate/etc/profile.d/conda.sh" ]; then
            # shellcheck disable=SC1091
            source "$candidate/etc/profile.d/conda.sh"
            break
        fi
    done
fi

if command -v conda >/dev/null 2>&1; then
    pass "'conda' command available"
else
    fail "'conda' command not found on PATH"
    echo
    echo "Summary: FAILED. Run scripts/install/install_pyscenic_pycistarget.sh first."
    echo "If the installation already ran, close and reopen your terminal (or run"
    echo "'source ~/.bashrc') for the 'conda init' done by the installer to take effect."
    exit 1
fi

# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

# install_pyscenic_pycistarget.sh creates environments by explicit prefix
# under the base install's envs/ dir (not by name), specifically so a
# pre-existing, customized envs_dirs config elsewhere on the machine can't
# hide them. Check/activate the same way here, for the same reason.
CONDA_BASE="$(conda info --base)"
ENV_PYSCENIC_PREFIX="$CONDA_BASE/envs/$ENV_PYSCENIC"
ENV_PYCISTARGET_PREFIX="$CONDA_BASE/envs/$ENV_PYCISTARGET"

# ---------------------------------------------------------------------------
# "$ENV_PYSCENIC" environment
# ---------------------------------------------------------------------------
echo
echo "--- Environment '$ENV_PYSCENIC' (pyscenic grn/ctx) ---"
if [ -d "$ENV_PYSCENIC_PREFIX" ]; then
    pass "conda environment '$ENV_PYSCENIC' exists ($ENV_PYSCENIC_PREFIX)"
    conda activate "$ENV_PYSCENIC_PREFIX"

    if pyscenic --help >/dev/null 2>&1; then
        pass "'pyscenic' command works"
    else
        fail "'pyscenic --help' failed (run 'conda activate $ENV_PYSCENIC && pyscenic --help' to see the full error)"
    fi

    for mod in pyscenic numpy numba dask arboreto ctxcore loompy; do
        if python -c "import $mod" >/dev/null 2>&1; then
            version=$(python -c "import $mod; print(getattr($mod, '__version__', 'no __version__'))" 2>/dev/null)
            pass "import $mod OK (version: $version)"
        else
            fail "could not import '$mod' in the '$ENV_PYSCENIC' environment"
        fi
    done

    # numpy>=1.24 removed np.object/np.bool/np.int, which pyscenic 0.12.1
    # uses directly — this imports without error but breaks in real use, so
    # check the version explicitly instead of just the import.
    if python -c "
import numpy, sys
major, minor = (int(x) for x in numpy.__version__.split('.')[:2])
sys.exit(0 if (major, minor) < (1, 24) else 1)
" >/dev/null 2>&1; then
        pass "numpy version is compatible with pyscenic 0.12.1 (<1.24)"
    else
        fail "numpy is at version >=1.24, incompatible with pyscenic 0.12.1 (see install_pyscenic_pycistarget.sh)"
    fi

    # dask>=2024.3.0 uses the dask-expr backend, which breaks 'pyscenic grn'
    # (arboreto 0.1.6 calls from_delayed with an empty list by default).
    if python -c "
import dask, sys
year, month = (int(x) for x in dask.__version__.split('.')[:2])
sys.exit(0 if (year, month) < (2024, 3) else 1)
" >/dev/null 2>&1; then
        pass "dask version is compatible with 'pyscenic grn' (before the dask-expr backend)"
    else
        fail "dask is at version >=2024.3.0 (dask-expr backend), incompatible with 'pyscenic grn' (see install_pyscenic_pycistarget.sh)"
    fi

    conda deactivate
else
    fail "conda environment '$ENV_PYSCENIC' does not exist"
fi

# ---------------------------------------------------------------------------
# "$ENV_PYCISTARGET" environment
# ---------------------------------------------------------------------------
echo
echo "--- Environment '$ENV_PYCISTARGET' (pycistarget) ---"
if [ -d "$ENV_PYCISTARGET_PREFIX" ]; then
    pass "conda environment '$ENV_PYCISTARGET' exists ($ENV_PYCISTARGET_PREFIX)"
    conda activate "$ENV_PYCISTARGET_PREFIX"

    if python -c "import pycistarget" >/dev/null 2>&1; then
        version=$(python -c "import pycistarget; print(getattr(pycistarget, '__version__', 'no __version__'))" 2>/dev/null)
        pass "import pycistarget OK (version: $version)"
    else
        fail "could not import 'pycistarget' in the '$ENV_PYCISTARGET' environment (run 'conda activate $ENV_PYCISTARGET && python -c \"import pycistarget\"' to see the full error)"
    fi

    conda deactivate
else
    fail "conda environment '$ENV_PYCISTARGET' does not exist"
fi

# ---------------------------------------------------------------------------
# Informational
# ---------------------------------------------------------------------------
echo
CORES=$(nproc 2>/dev/null || echo "?")
echo "[INFO] CPU cores available on this machine: $CORES"
echo "[INFO] adjust the num_workers column in the configs/ CSVs to not exceed that value"

echo
if [ "$FAILED" -eq 0 ]; then
    echo "Summary: ALL OK. Environments ready to use."
    exit 0
else
    echo "Summary: FAILED at least one check above. Review the installation."
    exit 1
fi
