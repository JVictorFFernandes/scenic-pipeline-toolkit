#!/bin/bash
#
# Baixa os arquivos REAIS e oficiais do cisTarget (resources.aertslab.org) e
# monta um conjunto de dados sintético (genes/FTs reais, expressão
# aleatória) para testar o 'pyscenic grn' + 'pyscenic ctx' de ponta a ponta
# com arquivos oficiais, antes de ter dados reais de scRNA-seq.
#
# Requer o ambiente 'scenic' ativado (usa o ctxcore para ler o banco de
# dados).
#
# Uso:
#   conda activate scenic
#   bash scripts/testes/setup_real_smoke_test.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

if ! python -c "import ctxcore" >/dev/null 2>&1; then
    echo "ERRO: ative o ambiente 'scenic' primeiro (conda activate scenic)."
    exit 1
fi

mkdir -p downloads/cistarget data artefatos/exemplos/outs/smoke_test

FEATHER_URL="https://resources.aertslab.org/cistarget/databases/homo_sapiens/hg38/refseq_r80/mc_v10_clust/gene_based/hg38_10kbp_up_10kbp_down_full_tx_v10_clust.genes_vs_motifs.rankings.feather"
TBL_URL="https://resources.aertslab.org/cistarget/motif2tf/motifs-v10nr_clust-nr.hgnc-m0.001-o0.0.tbl"
TFS_URL="https://raw.githubusercontent.com/aertslab/pySCENIC/master/resources/hs_hgnc_tfs.txt"

FEATHER_PATH="downloads/cistarget/hg38_10kbp_up_10kbp_down_full_tx_v10_clust.genes_vs_motifs.rankings.feather"
TBL_PATH="downloads/cistarget/motifs-v10nr_clust-nr.hgnc-m0.001-o0.0.tbl"
TFS_PATH="downloads/hs_hgnc_tfs.txt"

download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        echo "Já existe, pulando: $dest"
    else
        echo "Baixando: $dest"
        curl -L --fail -o "${dest}.part" "$url"
        mv "${dest}.part" "$dest"
    fi
}

echo "=== 1/3 Banco de dados real de rankings hg38 do cisTarget (~297 MB) ==="
download "$FEATHER_URL" "$FEATHER_PATH"

echo "=== 2/3 Tabela de anotação de motivos (~94 MB) ==="
download "$TBL_URL" "$TBL_PATH"

echo "=== 3/3 Lista de FTs humanos (aertslab/pySCENIC) ==="
download "$TFS_URL" "$TFS_PATH"

echo
echo "=== Gerando um conjunto de dados sintético com genes/FTs REAIS ==="
python "$SCRIPT_DIR/make_smoke_test_loom.py" \
    --feather "$FEATHER_PATH" \
    --tfs "$TFS_PATH" \
    --out-loom data/smoke_test.loom \
    --out-tfs data/smoke_test_tfs.txt \
    --n-genes 300 \
    --n-tfs 30 \
    --n-cells 150

cat > artefatos/exemplos/grn_smoke_test.csv <<EOF
run_id,loom_path,tfs_path,output_path,num_workers,method,seed
smoke_test,data/smoke_test.loom,data/smoke_test_tfs.txt,artefatos/exemplos/outs/smoke_test/adj_smoke_test.tsv,4,grnboost2,1
EOF

# nes_threshold definido bem baixo apenas para este teste mecânico: como a
# expressão é ruído aleatório, é pouco provável que passe pelo limiar padrão
# (2.5) de uma análise real. O objetivo aqui é confirmar que o comando
# executa e grava a saída no formato correto com os arquivos oficiais, não
# encontrar regulons biologicamente válidos.
cat > artefatos/exemplos/ctx_smoke_test.csv <<EOF
run_id,tf_name,adj_path,feather_path,tbl_path,loom_path,nes_threshold,mode,num_workers,output_path
smoke_test,ALL,artefatos/exemplos/outs/smoke_test/adj_smoke_test.tsv,$FEATHER_PATH,$TBL_PATH,data/smoke_test.loom,0.0,dask_multiprocessing,4,artefatos/exemplos/outs/smoke_test/reg_smoke_test.csv
EOF

echo
echo "Concluído. Agora execute, nesta ordem:"
echo "    bash scripts/run_pyscenic_grn.sh artefatos/exemplos/grn_smoke_test.csv"
echo "    bash scripts/run_pyscenic_ctx.sh artefatos/exemplos/ctx_smoke_test.csv"
