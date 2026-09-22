#!/bin/bash

set -e  # para se der erro

echo "Executando rede 37..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n37.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Executando rede 38..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n38.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Executando rede 39..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n39.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Executando rede 40..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n40.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Executando rede 41..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n41.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Executando rede 42..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n42.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt
echo "Concluído!"
