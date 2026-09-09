#!/bin/bash
#
# Downloads the REAL, official cisTarget files (resources.aertslab.org) and
# builds a synthetic dataset (real genes/TFs, random expression) to test
# 'pyscenic grn' + 'pyscenic ctx' end-to-end with official files, before
# having real scRNA-seq data.
#
# Requires the 'scenic' environment to be activated (uses ctxcore to read
# the database).
#
# Usage:
#   conda activate scenic
#   bash scripts/tests/setup_real_smoke_test.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

if ! python -c "import ctxcore" >/dev/null 2>&1; then
    echo "ERROR: activate the 'scenic' environment first (conda activate scenic)."
    exit 1
fi

mkdir -p downloads/cistarget data outs/smoke_test

FEATHER_URL="https://resources.aertslab.org/cistarget/databases/homo_sapiens/hg38/refseq_r80/mc_v10_clust/gene_based/hg38_10kbp_up_10kbp_down_full_tx_v10_clust.genes_vs_motifs.rankings.feather"
TBL_URL="https://resources.aertslab.org/cistarget/motif2tf/motifs-v10nr_clust-nr.hgnc-m0.001-o0.0.tbl"
TFS_URL="https://raw.githubusercontent.com/aertslab/pySCENIC/master/resources/hs_hgnc_tfs.txt"

FEATHER_PATH="downloads/cistarget/hg38_10kbp_up_10kbp_down_full_tx_v10_clust.genes_vs_motifs.rankings.feather"
TBL_PATH="downloads/cistarget/motifs-v10nr_clust-nr.hgnc-m0.001-o0.0.tbl"
TFS_PATH="downloads/hs_hgnc_tfs.txt"

download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        echo "Already exists, skipping: $dest"
    else
        echo "Downloading: $dest"
        curl -L --fail -o "${dest}.part" "$url"
        mv "${dest}.part" "$dest"
    fi
}

echo "=== 1/3 Real cisTarget hg38 rankings database (~297 MB) ==="
download "$FEATHER_URL" "$FEATHER_PATH"

echo "=== 2/3 Motif annotation table (~94 MB) ==="
download "$TBL_URL" "$TBL_PATH"

echo "=== 3/3 Human TF list (aertslab/pySCENIC) ==="
download "$TFS_URL" "$TFS_PATH"

echo
echo "=== Generating a synthetic dataset with REAL genes/TFs ==="
python "$SCRIPT_DIR/make_smoke_test_loom.py" \
    --feather "$FEATHER_PATH" \
    --tfs "$TFS_PATH" \
    --out-loom data/smoke_test.loom \
    --out-tfs data/smoke_test_tfs.txt \
    --n-genes 300 \
    --n-tfs 30 \
    --n-cells 150

cat > configs/examples/grn_smoke_test.csv <<EOF
run_id,loom_path,tfs_path,output_path,num_workers,method,seed
smoke_test,data/smoke_test.loom,data/smoke_test_tfs.txt,outs/smoke_test/adj_smoke_test.tsv,4,grnboost2,1
EOF

# nes_threshold set very low only for this mechanical test: since the
# expression is random noise, it's unlikely to pass the default threshold
# (2.5) of a real analysis. The goal here is to confirm the command runs and
# writes output in the correct format with the official files, not to find
# biologically valid regulons.
cat > configs/examples/ctx_smoke_test.csv <<EOF
run_id,tf_name,adj_path,feather_path,tbl_path,loom_path,nes_threshold,mode,num_workers,output_path
smoke_test,ALL,outs/smoke_test/adj_smoke_test.tsv,$FEATHER_PATH,$TBL_PATH,data/smoke_test.loom,0.0,dask_multiprocessing,4,outs/smoke_test/reg_smoke_test.csv
EOF

echo
echo "Done. Now run, in this order:"
echo "    bash scripts/run_pyscenic_grn.sh configs/examples/grn_smoke_test.csv"
echo "    bash scripts/run_pyscenic_ctx.sh configs/examples/ctx_smoke_test.csv"