#!/bin/bash

set -e  # stop on error

echo "Running network 37..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n37.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Running network 38..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n38.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Running network 39..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n39.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Running network 40..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n40.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Running network 41..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n41.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt

echo "Running network 42..."
pyscenic grn   --num_workers 6   --output outs/adj_Hepg2_n42.tsv   --method grnboost2   data/Hepg2_GSM5677000_filtered_scenic.loom   downloads/hs_hgnc_tfs.txt
echo "Done!"
