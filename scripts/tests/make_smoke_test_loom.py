#!/usr/bin/env python
"""
Generates a synthetic .loom using REAL genes and TFs (extracted from the
cisTarget database downloaded from resources.aertslab.org), to test the
grn+ctx pipeline end-to-end with official files before having real scRNA-seq
data.

Expression values are random noise (Poisson) — this tests the pipeline's
MECHANICS (commands run, read the real files, write output in the correct
format), not real biology. Regulons found here have no biological meaning.
"""
import argparse
import random

import numpy as np
import loompy
from ctxcore.rnkdb import FeatherRankingDatabase


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feather", required=True, help="cisTarget rankings database (.feather)")
    parser.add_argument("--tfs", required=True, help="human TF list (.txt, one per line)")
    parser.add_argument("--out-loom", required=True, help="path of the synthetic .loom to create")
    parser.add_argument("--out-tfs", required=True, help="path of the reduced TF list to create")
    parser.add_argument("--n-genes", type=int, default=300, help="total genes in the synthetic loom")
    parser.add_argument("--n-tfs", type=int, default=30, help="how many of those genes are TFs")
    parser.add_argument("--n-cells", type=int, default=150, help="number of synthetic cells")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    print(f"Reading genes available in the cisTarget database: {args.feather}")
    db = FeatherRankingDatabase(fname=args.feather, name="smoke_test_db")
    db_genes = set(db.genes)
    print(f"  -> {len(db_genes)} genes in the database")

    with open(args.tfs) as fh:
        all_tfs = [line.strip() for line in fh if line.strip()]
    tfs_in_db = sorted(db_genes.intersection(all_tfs))
    print(f"  -> {len(tfs_in_db)} TFs from '{args.tfs}' exist in the database")

    if len(tfs_in_db) < args.n_tfs:
        raise SystemExit(
            f"Only found {len(tfs_in_db)} TFs in common between {args.tfs} and the cisTarget "
            f"database, but --n-tfs asks for {args.n_tfs}. Reduce --n-tfs."
        )

    chosen_tfs = random.sample(tfs_in_db, args.n_tfs)

    other_genes_pool = sorted(db_genes - set(chosen_tfs))
    n_other = args.n_genes - args.n_tfs
    if len(other_genes_pool) < n_other:
        raise SystemExit(f"cisTarget database doesn't have enough genes for --n-genes {args.n_genes}.")
    chosen_others = random.sample(other_genes_pool, n_other)

    genes = chosen_tfs + chosen_others
    random.shuffle(genes)

    print(f"Generating synthetic matrix: {len(genes)} genes x {args.n_cells} cells (Poisson noise)")
    matrix = np.random.poisson(3, size=(len(genes), args.n_cells)).astype(float)
    row_attrs = {"Gene": np.array(genes)}
    col_attrs = {"CellID": np.array([f"cell{i}" for i in range(args.n_cells)])}
    loompy.create(args.out_loom, matrix, row_attrs, col_attrs)
    print(f"  -> loom saved to {args.out_loom}")

    with open(args.out_tfs, "w") as fh:
        fh.write("\n".join(chosen_tfs) + "\n")
    print(f"  -> {len(chosen_tfs)} TFs saved to {args.out_tfs}")
    print("\nWARNING: expression is random noise — this validates that the pipeline RUNS")
    print("with real cisTarget files, not that the regulons found make biological")
    print("sense. That only comes from real scRNA-seq data.")


if __name__ == "__main__":
    main()