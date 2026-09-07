#!/bin/bash
#
# Installs everything needed to run pySCENIC + pycistarget on a clean Ubuntu
# server. Idempotent: can be run again without breaking anything already
# installed (each step checks before acting).
#
# IMPORTANT: pyscenic and pycistarget have incompatible transitive
# dependencies (e.g. pycistarget pulls in pyranges, which requires
# pandas<2.0; the dask used by pyscenic requires pandas>=2.0). That's why
# they're installed in TWO separate conda environments, not the same one.
# The scripts in scripts/run_pyscenic_*.sh only need the "$ENV_PYSCENIC"
# environment (they don't use pycistarget).
#
# Usage:
#   bash scripts/install/install_pyscenic_pycistarget.sh
#
# After running, validate with:
#   bash scripts/install/verify_installation.sh
#
set -euo pipefail

ENV_PYSCENIC="scenic"
ENV_PYCISTARGET="pycistarget"
PYTHON_VERSION_PYSCENIC="3.10"
PYTHON_VERSION_PYCISTARGET="3.11"
MINIFORGE_DIR="$HOME/miniforge3"
PYSCENIC_VERSION="0.12.1"
PYCISTARGET_REF="v1.1"  # GitHub tag (not on PyPI, see installation below)
# setuptools>=82 removed the pkg_resources module, which ctxcore and
# pycistarget (older packages) still import directly. We pin it below 82.
SETUPTOOLS_SPEC="setuptools<82"
# pyscenic 0.12.1 uses np.object/np.bool/np.int directly in its source code
# — aliases that NumPy removed in version 1.24 (Dec/2022). Without pinning
# an older version, pip installs the latest numpy available and pyscenic
# breaks. numba==0.56.4 is the version compatible with numpy 1.18-1.23
# (official numba support matrix), and llvmlite==0.39.1 is the one that
# pairs with that numba.
NUMPY_SPEC="numpy==1.23.5"
NUMBA_SPEC="numba==0.56.4"
LLVMLITE_SPEC="llvmlite==0.39.1"
# arboreto 0.1.6 (used by "pyscenic grn") calls dask.dataframe.from_delayed
# with an EMPTY list by default (include_meta=False) — this was always
# tolerated by "classic" dask, but since version 2024.03.0 the new
# dask-expr backend started raising an error in this case ("Must supply at
# least one delayed object"). We pin dask/distributed to a version before
# that change.
DASK_SPEC="dask[dataframe]==2023.5.0"
DISTRIBUTED_SPEC="distributed==2023.5.0"

log() { echo -e "\n=== $* ==="; }

# ---------------------------------------------------------------------------
# 1) System dependencies (apt)
# ---------------------------------------------------------------------------
log "1/6 System dependencies (apt)"
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    python3-dev \
    libhdf5-dev \
    pkg-config \
    zlib1g-dev

# ---------------------------------------------------------------------------
# 2) Conda/Mamba (Miniforge)
# ---------------------------------------------------------------------------
log "2/6 Conda/Mamba (Miniforge)"
if command -v mamba >/dev/null 2>&1; then
    echo "mamba is already installed, skipping Miniforge installation."
elif command -v conda >/dev/null 2>&1; then
    echo "conda is already installed, skipping Miniforge installation (will install mamba into it)."
else
    if [ -d "$MINIFORGE_DIR" ]; then
        echo "Directory $MINIFORGE_DIR already exists, skipping download."
    else
        echo "Downloading and installing Miniforge to $MINIFORGE_DIR ..."
        TMP_INSTALLER=$(mktemp /tmp/miniforge_XXXX.sh)
        curl -L -o "$TMP_INSTALLER" \
            "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
        bash "$TMP_INSTALLER" -b -p "$MINIFORGE_DIR"
        rm -f "$TMP_INSTALLER"
    fi
    # shellcheck disable=SC1091
    source "$MINIFORGE_DIR/etc/profile.d/conda.sh"
fi

# Make sure 'conda' is available in this shell session, even if it was
# already installed in a non-standard path detected above.
if ! command -v conda >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$MINIFORGE_DIR/etc/profile.d/conda.sh"
fi

if ! command -v mamba >/dev/null 2>&1; then
    echo "Installing mamba into the base environment..."
    conda install -n base -y -c conda-forge mamba
fi

# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

# ---------------------------------------------------------------------------
# 3) Conda environment "$ENV_PYSCENIC" (pyscenic only — used by scripts/run_pyscenic_*.sh)
# ---------------------------------------------------------------------------
log "3/6 Conda environment '$ENV_PYSCENIC' (Python $PYTHON_VERSION_PYSCENIC)"
if conda env list | grep -qE "^${ENV_PYSCENIC}\s"; then
    echo "Environment '$ENV_PYSCENIC' already exists, skipping creation."
else
    mamba create -n "$ENV_PYSCENIC" -y -c conda-forge "python=$PYTHON_VERSION_PYSCENIC" pip "$SETUPTOOLS_SPEC" wheel
fi

conda activate "$ENV_PYSCENIC"

# If pycistarget was installed by mistake in this environment on a previous
# attempt, it already broke pyscenic's pandas/dask — detect and warn instead
# of proceeding with a contaminated environment.
if python -c "import pycistarget" >/dev/null 2>&1; then
    echo
    echo "ERROR: the '$ENV_PYSCENIC' environment has 'pycistarget' installed in it,"
    echo "which breaks pyscenic's dependencies (pandas version conflict)."
    echo "Run the following to fix it, then run this script again:"
    echo "    conda deactivate"
    echo "    conda env remove -n $ENV_PYSCENIC -y"
    exit 1
fi

log "4/6 pyscenic (pip, environment '$ENV_PYSCENIC')"
python -m pip install --upgrade pip "$SETUPTOOLS_SPEC" wheel

# Check whether everything is already at the right version (real
# idempotency, not just "imports without error" — a too-new numpy IMPORTS
# fine, it only breaks once it's actually used).
NEEDS_INSTALL=0
if ! python -c "import pyscenic" >/dev/null 2>&1; then
    NEEDS_INSTALL=1
fi
if ! python -c "import numpy; assert numpy.__version__ == '1.23.5'" >/dev/null 2>&1; then
    NEEDS_INSTALL=1
fi
if ! python -c "import dask; assert dask.__version__ == '2023.5.0'" >/dev/null 2>&1; then
    NEEDS_INSTALL=1
fi

if [ "$NEEDS_INSTALL" -eq 0 ]; then
    echo "pyscenic + numpy/numba/llvmlite/dask are already at the right versions in '$ENV_PYSCENIC', skipping."
else
    # Installed together in a single call so pip's resolver gets the
    # compatible versions right in one go, instead of installing then fixing.
    pip install "$NUMPY_SPEC" "$NUMBA_SPEC" "$LLVMLITE_SPEC" "$DASK_SPEC" "$DISTRIBUTED_SPEC" "pyscenic==${PYSCENIC_VERSION}"
fi
# dask-expr (the new backend's package) may be left orphaned from a previous
# attempt with a newer dask — dask 2023.5.0 doesn't use or need it.
if python -c "import dask_expr" >/dev/null 2>&1; then
    pip uninstall -y dask-expr
fi
# Re-enforce the pins after installation, in case some dependency pulled in
# newer versions without meaning to.
pip install --upgrade "$SETUPTOOLS_SPEC" "$NUMPY_SPEC" "$NUMBA_SPEC" "$LLVMLITE_SPEC" "$DASK_SPEC" "$DISTRIBUTED_SPEC"

conda deactivate

# ---------------------------------------------------------------------------
# 5) Conda environment "$ENV_PYCISTARGET" (separate, avoids dependency conflicts)
# ---------------------------------------------------------------------------
log "5/6 Conda environment '$ENV_PYCISTARGET' (Python $PYTHON_VERSION_PYCISTARGET)"
if conda env list | grep -qE "^${ENV_PYCISTARGET}\s"; then
    echo "Environment '$ENV_PYCISTARGET' already exists, skipping creation."
else
    mamba create -n "$ENV_PYCISTARGET" -y -c conda-forge "python=$PYTHON_VERSION_PYCISTARGET" pip "$SETUPTOOLS_SPEC" wheel
fi

conda activate "$ENV_PYCISTARGET"
python -m pip install --upgrade pip "$SETUPTOOLS_SPEC" wheel

if python -c "import pycistarget" >/dev/null 2>&1; then
    echo "pycistarget is already installed in '$ENV_PYCISTARGET', skipping."
else
    # pycistarget is NOT published on PyPI (only pyscenic is) — it needs to
    # be installed directly from GitHub.
    pip install "git+https://github.com/aertslab/pycistarget.git@${PYCISTARGET_REF}"
fi
pip install --upgrade "$SETUPTOOLS_SPEC"

conda deactivate

# ---------------------------------------------------------------------------
# 6) Make 'conda' available in new terminal sessions
# ---------------------------------------------------------------------------
# Silent-mode installers (-b) don't touch .bashrc. Without this, a new
# terminal won't find the 'conda' command even though everything is
# installed.
CONDA_BASE="$(conda info --base)"
if ! grep -q "conda initialize" "$HOME/.bashrc" 2>/dev/null; then
    log "6/6 Registering conda in ~/.bashrc (conda init bash)"
    "$CONDA_BASE/bin/conda" init bash
else
    echo "~/.bashrc already has the 'conda init' block, skipping."
fi

log "Installation complete"
echo "Environment '$ENV_PYSCENIC'      -> use for 'pyscenic grn' and 'pyscenic ctx' (scripts/run_pyscenic_*.sh)"
echo "Environment '$ENV_PYCISTARGET' -> use for pycistarget analyses"
echo
echo "IMPORTANT: close and reopen your terminal (or run 'source ~/.bashrc')"
echo "for the 'conda' command to start working in new sessions."
echo
echo "After that, in any new session:"
echo "    conda activate $ENV_PYSCENIC       # to run the grn/ctx scripts"
echo "    conda activate $ENV_PYCISTARGET    # to work with pycistarget"
echo
echo "To confirm everything is working, run:"
echo "    bash scripts/install/verify_installation.sh"
