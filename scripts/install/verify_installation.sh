#!/bin/bash
#
# Smoke test para a instalação feita pelo install_pyscenic_pycistarget.sh.
# Execute isso após a instalação para confirmar que está tudo certo antes de
# iniciar execuções reais. Não usa 'set -e': queremos rodar TODAS as
# verificações e mostrar um resumo final, mesmo se uma delas falhar.
#
# O pyscenic e o pycistarget vivem em ambientes conda SEPARADOS (veja o
# comentário no topo do install_pyscenic_pycistarget.sh sobre o conflito de
# pandas).
#
# Uso:
#   bash scripts/install/verify_installation.sh
#
ENV_PYSCENIC="scenic"
ENV_PYCISTARGET="pycistarget"
FAILED=0

pass() { echo "[ OK ] $*"; }
fail() { echo "[FAIL] $*"; FAILED=1; }

echo "=== Verificando a instalação ==="

# 0) conda disponível
# Se o terminal atual foi aberto antes de o 'conda init' rodar (ou você não
# reabriu o terminal após a instalação), o 'conda' pode ainda não estar no
# PATH mesmo estando instalado. Tenta encontrá-lo nos locais usuais antes de
# desistir.
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
    pass "comando 'conda' disponível"
else
    fail "comando 'conda' não encontrado no PATH"
    echo
    echo "Resumo: FALHOU. Execute primeiro scripts/install/install_pyscenic_pycistarget.sh."
    echo "Se a instalação já foi executada, feche e reabra seu terminal (ou execute"
    echo "'source ~/.bashrc') para que o 'conda init' feito pelo instalador tenha efeito."
    exit 1
fi

# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

# o install_pyscenic_pycistarget.sh cria os ambientes por um prefixo
# explícito sob o diretório envs/ da instalação base (não por nome),
# especificamente para que uma configuração pré-existente e customizada de
# envs_dirs em outro lugar da máquina não consiga escondê-los. Verifica/ativa
# da mesma forma aqui, pelo mesmo motivo.
CONDA_BASE="$(conda info --base)"
ENV_PYSCENIC_PREFIX="$CONDA_BASE/envs/$ENV_PYSCENIC"
ENV_PYCISTARGET_PREFIX="$CONDA_BASE/envs/$ENV_PYCISTARGET"

# ---------------------------------------------------------------------------
# Ambiente "$ENV_PYSCENIC"
# ---------------------------------------------------------------------------
echo
echo "--- Ambiente '$ENV_PYSCENIC' (pyscenic grn/ctx) ---"
if [ -d "$ENV_PYSCENIC_PREFIX" ]; then
    pass "o ambiente conda '$ENV_PYSCENIC' existe ($ENV_PYSCENIC_PREFIX)"
    conda activate "$ENV_PYSCENIC_PREFIX"

    if pyscenic --help >/dev/null 2>&1; then
        pass "o comando 'pyscenic' funciona"
    else
        fail "'pyscenic --help' falhou (execute 'conda activate $ENV_PYSCENIC && pyscenic --help' para ver o erro completo)"
    fi

    for mod in pyscenic numpy numba dask arboreto ctxcore loompy; do
        if python -c "import $mod" >/dev/null 2>&1; then
            version=$(python -c "import $mod; print(getattr($mod, '__version__', 'sem __version__'))" 2>/dev/null)
            pass "import $mod OK (versão: $version)"
        else
            fail "não foi possível importar '$mod' no ambiente '$ENV_PYSCENIC'"
        fi
    done

    # numpy>=1.24 removeu np.object/np.bool/np.int, que o pyscenic 0.12.1 usa
    # diretamente — isso importa sem erro, mas quebra no uso real, então
    # verificamos a versão explicitamente em vez de apenas o import.
    if python -c "
import numpy, sys
major, minor = (int(x) for x in numpy.__version__.split('.')[:2])
sys.exit(0 if (major, minor) < (1, 24) else 1)
" >/dev/null 2>&1; then
        pass "a versão do numpy é compatível com o pyscenic 0.12.1 (<1.24)"
    else
        fail "o numpy está na versão >=1.24, incompatível com o pyscenic 0.12.1 (veja install_pyscenic_pycistarget.sh)"
    fi

    # dask>=2024.3.0 usa o backend dask-expr, que quebra o 'pyscenic grn'
    # (o arboreto 0.1.6 chama from_delayed com uma lista vazia por padrão).
    if python -c "
import dask, sys
year, month = (int(x) for x in dask.__version__.split('.')[:2])
sys.exit(0 if (year, month) < (2024, 3) else 1)
" >/dev/null 2>&1; then
        pass "a versão do dask é compatível com o 'pyscenic grn' (anterior ao backend dask-expr)"
    else
        fail "o dask está na versão >=2024.3.0 (backend dask-expr), incompatível com o 'pyscenic grn' (veja install_pyscenic_pycistarget.sh)"
    fi

    conda deactivate
else
    fail "o ambiente conda '$ENV_PYSCENIC' não existe"
fi

# ---------------------------------------------------------------------------
# Ambiente "$ENV_PYCISTARGET"
# ---------------------------------------------------------------------------
echo
echo "--- Ambiente '$ENV_PYCISTARGET' (pycistarget) ---"
if [ -d "$ENV_PYCISTARGET_PREFIX" ]; then
    pass "o ambiente conda '$ENV_PYCISTARGET' existe ($ENV_PYCISTARGET_PREFIX)"
    conda activate "$ENV_PYCISTARGET_PREFIX"

    if python -c "import pycistarget" >/dev/null 2>&1; then
        version=$(python -c "import pycistarget; print(getattr(pycistarget, '__version__', 'sem __version__'))" 2>/dev/null)
        pass "import pycistarget OK (versão: $version)"
    else
        fail "não foi possível importar 'pycistarget' no ambiente '$ENV_PYCISTARGET' (execute 'conda activate $ENV_PYCISTARGET && python -c \"import pycistarget\"' para ver o erro completo)"
    fi

    conda deactivate
else
    fail "o ambiente conda '$ENV_PYCISTARGET' não existe"
fi

# ---------------------------------------------------------------------------
# Informativo
# ---------------------------------------------------------------------------
echo
CORES=$(nproc 2>/dev/null || echo "?")
echo "[INFO] núcleos de CPU disponíveis nesta máquina: $CORES"
echo "[INFO] ajuste a coluna num_workers nos CSVs de configs/ para não exceder esse valor"

echo
if [ "$FAILED" -eq 0 ]; then
    echo "Resumo: TUDO OK. Ambientes prontos para uso."
    exit 0
else
    echo "Resumo: FALHOU em pelo menos uma verificação acima. Revise a instalação."
    exit 1
fi
