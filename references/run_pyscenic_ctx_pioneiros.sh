#!/bin/bash

set -e  # para se der erro

echo "Running ATF4..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_ATF4.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_ATF4.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_ATF4_th25.csv     --num_workers 6     --mask_dropouts

echo "Running CEBPB..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_CEBPB.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_CEBPB.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_CEBPB_th25.csv     --num_workers 6     --mask_dropouts

echo "Running JUND..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_JUND.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_JUND.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_JUND_th25.csv     --num_workers 6     --mask_dropouts

echo "Running JUN..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_JUN.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_JUN.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_JUN_th25.csv     --num_workers 6     --mask_dropouts

echo "Running FOSL1..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_FOSL1.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_FOSL1.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_FOSL1_th25.csv     --num_workers 6     --mask_dropouts

echo "Running ATF3..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_ATF3.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_ATF3.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_ATF3_th25.csv     --num_workers 6     --mask_dropouts

echo "Running ATF2..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_ATF2.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_ATF2.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_ATF2_th25.csv     --num_workers 6     --mask_dropouts

echo "Running MAFF..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_MAFF.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_MAFF.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_MAFF_th25.csv     --num_workers 6     --mask_dropouts

echo "Running NFYB..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_NFYB.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_NFYB.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_NFYB_th25.csv     --num_workers 6     --mask_dropouts

echo "Running MAFG..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_MAFG.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_MAFG.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_MAFG_th25.csv     --num_workers 6     --mask_dropouts

echo "Running CEBPA..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_CEBPA.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_CEBPA.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_CEBPA_th25.csv     --num_workers 6     --mask_dropouts

echo "Running MAFK..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_MAFK.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_MAFK.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_MAFK_th25.csv     --num_workers 6     --mask_dropouts

echo "Running FOXA1..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_FOXA1.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_FOXA1.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_FOXA1_th25.csv     --num_workers 6     --mask_dropouts

echo "Running FOSL2..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_FOSL2.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_FOSL2.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_FOSL2_th25.csv     --num_workers 6     --mask_dropouts

echo "Running TP53..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_TP53.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_TP53.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_TP53_th25.csv     --num_workers 6     --mask_dropouts

echo "Running FOXA3..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_FOXA3.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_FOXA3.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_FOXA3_th25.csv     --num_workers 6     --mask_dropouts

echo "Running GATA2..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_GATA2.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_GATA2.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_GATA2_th25.csv     --num_workers 6     --mask_dropouts

echo "Running ATF6..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_ATF6.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_ATF6.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_ATF6_th25.csv     --num_workers 6     --mask_dropouts

echo "Running ATF7..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n27.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_ATF7.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_ATF7.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica27/reg_Hepg2_adj27_motifs_plus_ATF7_th25.csv     --num_workers 6     --mask_dropouts

echo "Running FOXA2..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n27.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_FOXA2.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_FOXA2.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica27/reg_Hepg2_adj27_motifs_plus_FOXA2_th25.csv     --num_workers 6     --mask_dropouts

echo "Running GATA4..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n27.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_GATA4.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_GATA4.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica27/reg_Hepg2_adj27_motifs_plus_GATA4_th25.csv     --num_workers 6     --mask_dropouts

echo "Running NFYA..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n27.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_NFYA.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_NFYA.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica27/reg_Hepg2_adj27_motifs_plus_NFYA_th25.csv     --num_workers 6     --mask_dropouts

echo "Running NFYC..."
pyscenic ctx     outs/adj_hepg2/adj_Hepg2_n30.tsv     data/feathers/pioneiros/motifs_plus_chip/ptf_unico/hg38__motifs_plus_NFYC.genes_vs_motifs.rankings.feather     --annotations_fname data/tbls/pioneiros/ptf_unico/motifs_plus_NFYC.tbl     --expression_mtx_fname data/Hepg2_GSM5677000_filtered_scenic.loom     --nes_threshold 2.5     --mode "dask_multiprocessing"     --output outs/regs_chip/tf_unico/ptf/Replica30/reg_Hepg2_adj30_motifs_plus_NFYC_th25.csv     --num_workers 6     --mask_dropouts

