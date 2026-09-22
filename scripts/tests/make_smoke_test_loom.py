#!/usr/bin/env python
"""
Gera um .loom sintético usando genes e FTs REAIS (extraídos do banco de
dados cisTarget baixado de resources.aertslab.org), para testar o pipeline
grn+ctx de ponta a ponta com arquivos oficiais antes de ter dados reais de
scRNA-seq.

Os valores de expressão são ruído aleatório (Poisson) — isso testa a
MECÂNICA do pipeline (comandos executam, leem os arquivos reais, escrevem a
saída no formato correto), não a biologia real. Os regulons encontrados aqui
não têm nenhum significado biológico.
"""
import argparse
import random

import numpy as np
import loompy
from ctxcore.rnkdb import FeatherRankingDatabase


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feather", required=True, help="banco de dados de rankings do cisTarget (.feather)")
    parser.add_argument("--tfs", required=True, help="lista de FTs humanos (.txt, um por linha)")
    parser.add_argument("--out-loom", required=True, help="caminho do .loom sintético a ser criado")
    parser.add_argument("--out-tfs", required=True, help="caminho da lista reduzida de FTs a ser criada")
    parser.add_argument("--n-genes", type=int, default=300, help="total de genes no loom sintético")
    parser.add_argument("--n-tfs", type=int, default=30, help="quantos desses genes são FTs")
    parser.add_argument("--n-cells", type=int, default=150, help="número de células sintéticas")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    print(f"Lendo genes disponíveis no banco de dados cisTarget: {args.feather}")
    db = FeatherRankingDatabase(fname=args.feather, name="smoke_test_db")
    db_genes = set(db.genes)
    print(f"  -> {len(db_genes)} genes no banco de dados")

    with open(args.tfs) as fh:
        all_tfs = [line.strip() for line in fh if line.strip()]
    tfs_in_db = sorted(db_genes.intersection(all_tfs))
    print(f"  -> {len(tfs_in_db)} FTs de '{args.tfs}' existem no banco de dados")

    if len(tfs_in_db) < args.n_tfs:
        raise SystemExit(
            f"Encontrados apenas {len(tfs_in_db)} FTs em comum entre {args.tfs} e o banco de "
            f"dados cisTarget, mas --n-tfs pede {args.n_tfs}. Reduza --n-tfs."
        )

    chosen_tfs = random.sample(tfs_in_db, args.n_tfs)

    other_genes_pool = sorted(db_genes - set(chosen_tfs))
    n_other = args.n_genes - args.n_tfs
    if len(other_genes_pool) < n_other:
        raise SystemExit(f"O banco de dados cisTarget não tem genes suficientes para --n-genes {args.n_genes}.")
    chosen_others = random.sample(other_genes_pool, n_other)

    genes = chosen_tfs + chosen_others
    random.shuffle(genes)

    print(f"Gerando matriz sintética: {len(genes)} genes x {args.n_cells} células (ruído Poisson)")
    matrix = np.random.poisson(3, size=(len(genes), args.n_cells)).astype(float)
    row_attrs = {"Gene": np.array(genes)}
    col_attrs = {"CellID": np.array([f"cell{i}" for i in range(args.n_cells)])}
    loompy.create(args.out_loom, matrix, row_attrs, col_attrs)
    print(f"  -> loom salvo em {args.out_loom}")

    with open(args.out_tfs, "w") as fh:
        fh.write("\n".join(chosen_tfs) + "\n")
    print(f"  -> {len(chosen_tfs)} FTs salvos em {args.out_tfs}")
    print("\nAVISO: a expressão é ruído aleatório — isso valida que o pipeline EXECUTA")
    print("com arquivos reais do cisTarget, não que os regulons encontrados fazem")
    print("sentido biológico. Isso só vem de dados reais de scRNA-seq.")


if __name__ == "__main__":
    main()
