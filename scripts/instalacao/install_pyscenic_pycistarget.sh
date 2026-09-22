#!/bin/bash
#
# Instala tudo o que é necessário para executar o pySCENIC + pycistarget em
# um servidor Ubuntu limpo. Idempotente: pode ser executado novamente sem
# quebrar nada já instalado (cada etapa verifica antes de agir).
#
# IMPORTANTE: o pyscenic e o pycistarget têm dependências transitivas
# incompatíveis (ex.: o pycistarget traz o pyranges, que exige pandas<2.0; o
# dask usado pelo pyscenic exige pandas>=2.0). Por isso são instalados em
# DOIS ambientes conda separados, não no mesmo. Os scripts em
# scripts/run_pyscenic_*.sh só precisam do ambiente "$ENV_PYSCENIC" (eles não
# usam o pycistarget).
#
# Uso:
#   bash scripts/instalacao/install_pyscenic_pycistarget.sh
#
# Após executar, valide com:
#   bash scripts/instalacao/verify_installation.sh
#
set -euo pipefail

ENV_PYSCENIC="scenic"
ENV_PYCISTARGET="pycistarget"
PYTHON_VERSION_PYSCENIC="3.10"
PYTHON_VERSION_PYCISTARGET="3.11"
MINIFORGE_DIR="$HOME/miniforge3"
PYSCENIC_VERSION="0.12.1"
PYCISTARGET_REF="v1.1"  # tag do GitHub (não está no PyPI, veja a instalação abaixo)
# setuptools>=82 removeu o módulo pkg_resources, que o ctxcore e o
# pycistarget (pacotes mais antigos) ainda importam diretamente. Fixamos a
# versão abaixo de 82.
SETUPTOOLS_SPEC="setuptools<82"
# pyscenic 0.12.1 usa np.object/np.bool/np.int diretamente em seu código-fonte
# — aliases que o NumPy removeu na versão 1.24 (dez/2022). Sem fixar uma
# versão mais antiga, o pip instala o numpy mais recente disponível e o
# pyscenic quebra. numba==0.56.4 é a versão compatível com numpy 1.18-1.23
# (matriz oficial de suporte do numba), e llvmlite==0.39.1 é a que combina
# com esse numba.
NUMPY_SPEC="numpy==1.23.5"
NUMBA_SPEC="numba==0.56.4"
LLVMLITE_SPEC="llvmlite==0.39.1"
# arboreto 0.1.6 (usado pelo "pyscenic grn") chama dask.dataframe.from_delayed
# com uma lista VAZIA por padrão (include_meta=False) — isso sempre foi
# tolerado pelo dask "clássico", mas a partir da versão 2024.03.0 o novo
# backend dask-expr passou a lançar um erro nesse caso ("Must supply at
# least one delayed object"). Fixamos o dask/distributed em uma versão
# anterior a essa mudança.
DASK_SPEC="dask[dataframe]==2023.5.0"
DISTRIBUTED_SPEC="distributed==2023.5.0"

log() { echo -e "\n=== $* ==="; }

# ---------------------------------------------------------------------------
# 1) Dependências do sistema (apt)
# ---------------------------------------------------------------------------
log "1/6 Dependências do sistema (apt)"
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
    echo "o mamba já está instalado, pulando a instalação do Miniforge."
elif command -v conda >/dev/null 2>&1; then
    echo "o conda já está instalado, pulando a instalação do Miniforge (o mamba será instalado nele)."
else
    if [ -d "$MINIFORGE_DIR" ]; then
        echo "O diretório $MINIFORGE_DIR já existe, pulando o download."
    else
        echo "Baixando e instalando o Miniforge em $MINIFORGE_DIR ..."
        TMP_INSTALLER=$(mktemp /tmp/miniforge_XXXX.sh)
        curl -L -o "$TMP_INSTALLER" \
            "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
        bash "$TMP_INSTALLER" -b -p "$MINIFORGE_DIR"
        rm -f "$TMP_INSTALLER"
    fi
    # shellcheck disable=SC1091
    source "$MINIFORGE_DIR/etc/profile.d/conda.sh"
fi

# Garante que o 'conda' esteja disponível nesta sessão de shell, mesmo se já
# tiver sido instalado em um caminho não padrão detectado acima.
if ! command -v conda >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$MINIFORGE_DIR/etc/profile.d/conda.sh"
fi

if ! command -v mamba >/dev/null 2>&1; then
    echo "Instalando o mamba no ambiente base..."
    conda install -n base -y -c conda-forge mamba
fi

# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

# Cria/ativa os ambientes por um prefixo EXPLÍCITO sob o diretório envs/ da
# própria instalação base, em vez de por nome (-n) — em uma máquina que já
# tem o conda/mamba configurado, um .condarc/.mambarc pré-existente pode
# definir um `envs_dirs` customizado (às vezes relativo), colocando
# silenciosamente um ambiente criado por nome em um lugar inesperado (ex.:
# dentro do diretório atual) e fazendo com que um `conda activate` por nome
# posterior falhe com "EnvironmentNameNotFound" mesmo o ambiente existindo
# em disco. Um prefixo sob o próprio diretório envs/ da base evita isso por
# completo, e continua sendo o mesmo lugar em que `conda activate <nome>`
# procura primeiro por padrão depois.
CONDA_BASE="$(conda info --base)"
ENV_PYSCENIC_PREFIX="$CONDA_BASE/envs/$ENV_PYSCENIC"
ENV_PYCISTARGET_PREFIX="$CONDA_BASE/envs/$ENV_PYCISTARGET"

# ---------------------------------------------------------------------------
# 3) Ambiente conda "$ENV_PYSCENIC" (apenas pyscenic — usado por scripts/run_pyscenic_*.sh)
# ---------------------------------------------------------------------------
log "3/6 Ambiente conda '$ENV_PYSCENIC' (Python $PYTHON_VERSION_PYSCENIC)"
if [ -d "$ENV_PYSCENIC_PREFIX" ]; then
    echo "O ambiente '$ENV_PYSCENIC' já existe em $ENV_PYSCENIC_PREFIX, pulando a criação."
else
    mamba create -p "$ENV_PYSCENIC_PREFIX" -y -c conda-forge "python=$PYTHON_VERSION_PYSCENIC" pip "$SETUPTOOLS_SPEC" wheel
fi

conda activate "$ENV_PYSCENIC_PREFIX"

# Se o pycistarget foi instalado por engano nesse ambiente em uma tentativa
# anterior, ele já quebrou o pandas/dask do pyscenic — detecta e avisa em
# vez de prosseguir com um ambiente contaminado.
if python -c "import pycistarget" >/dev/null 2>&1; then
    echo
    echo "ERRO: o ambiente '$ENV_PYSCENIC' tem o 'pycistarget' instalado nele,"
    echo "o que quebra as dependências do pyscenic (conflito de versão do pandas)."
    echo "Execute o seguinte para corrigir, e depois execute este script novamente:"
    echo "    conda deactivate"
    echo "    conda env remove -p $ENV_PYSCENIC_PREFIX -y"
    exit 1
fi

log "4/6 pyscenic (pip, ambiente '$ENV_PYSCENIC')"
python -m pip install --upgrade pip "$SETUPTOOLS_SPEC" wheel

# Verifica se tudo já está na versão correta (idempotência de verdade, não
# apenas "importa sem erro" — um numpy muito novo IMPORTA normalmente, só
# quebra quando de fato é usado).
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
    echo "pyscenic + numpy/numba/llvmlite/dask já estão nas versões corretas em '$ENV_PYSCENIC', pulando."
else
    # Instalados juntos em uma única chamada para que o resolvedor de
    # dependências do pip acerte as versões compatíveis de uma vez, em vez
    # de instalar e depois corrigir.
    pip install "$NUMPY_SPEC" "$NUMBA_SPEC" "$LLVMLITE_SPEC" "$DASK_SPEC" "$DISTRIBUTED_SPEC" "pyscenic==${PYSCENIC_VERSION}"
fi
# o dask-expr (o pacote do novo backend) pode ter ficado órfão de uma
# tentativa anterior com um dask mais novo — o dask 2023.5.0 não o usa nem
# precisa dele.
if python -c "import dask_expr" >/dev/null 2>&1; then
    pip uninstall -y dask-expr
fi
# Reforça as fixações de versão após a instalação, caso alguma dependência
# tenha trazido versões mais novas sem querer.
pip install --upgrade "$SETUPTOOLS_SPEC" "$NUMPY_SPEC" "$NUMBA_SPEC" "$LLVMLITE_SPEC" "$DASK_SPEC" "$DISTRIBUTED_SPEC"

conda deactivate

# ---------------------------------------------------------------------------
# 5) Ambiente conda "$ENV_PYCISTARGET" (separado, evita conflitos de dependências)
# ---------------------------------------------------------------------------
log "5/6 Ambiente conda '$ENV_PYCISTARGET' (Python $PYTHON_VERSION_PYCISTARGET)"
if [ -d "$ENV_PYCISTARGET_PREFIX" ]; then
    echo "O ambiente '$ENV_PYCISTARGET' já existe em $ENV_PYCISTARGET_PREFIX, pulando a criação."
else
    mamba create -p "$ENV_PYCISTARGET_PREFIX" -y -c conda-forge "python=$PYTHON_VERSION_PYCISTARGET" pip "$SETUPTOOLS_SPEC" wheel
fi

conda activate "$ENV_PYCISTARGET_PREFIX"
python -m pip install --upgrade pip "$SETUPTOOLS_SPEC" wheel

if python -c "import pycistarget" >/dev/null 2>&1; then
    echo "o pycistarget já está instalado em '$ENV_PYCISTARGET', pulando."
else
    # o pycistarget NÃO é publicado no PyPI (só o pyscenic é) — precisa ser
    # instalado diretamente do GitHub.
    pip install "git+https://github.com/aertslab/pycistarget.git@${PYCISTARGET_REF}"
fi
pip install --upgrade "$SETUPTOOLS_SPEC"

conda deactivate

# ---------------------------------------------------------------------------
# 6) Disponibiliza o 'conda' em novas sessões de terminal
# ---------------------------------------------------------------------------
# Instaladores em modo silencioso (-b) não alteram o .bashrc. Sem isso, um
# novo terminal não encontrará o comando 'conda' mesmo com tudo instalado.
if ! grep -q "conda initialize" "$HOME/.bashrc" 2>/dev/null; then
    log "6/6 Registrando o conda no ~/.bashrc (conda init bash)"
    "$CONDA_BASE/bin/conda" init bash
else
    echo "o ~/.bashrc já tem o bloco 'conda init', pulando."
fi

log "Instalação concluída"
echo "Ambiente '$ENV_PYSCENIC'      -> use para 'pyscenic grn' e 'pyscenic ctx' (scripts/run_pyscenic_*.sh)"
echo "Ambiente '$ENV_PYCISTARGET' -> use para análises com o pycistarget"
echo
echo "IMPORTANTE: feche e reabra seu terminal (ou execute 'source ~/.bashrc')"
echo "para que o comando 'conda' passe a funcionar em novas sessões."
echo
echo "Depois disso, em qualquer nova sessão:"
echo "    conda activate $ENV_PYSCENIC       # para executar os scripts de grn/ctx"
echo "    conda activate $ENV_PYCISTARGET    # para trabalhar com o pycistarget"
echo
echo "Para confirmar que tudo está funcionando, execute:"
echo "    bash scripts/instalacao/verify_installation.sh"
