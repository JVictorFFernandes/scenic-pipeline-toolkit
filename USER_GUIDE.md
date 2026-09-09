# User Guide

A step-by-step walkthrough for setting up this toolkit on a brand-new
Ubuntu machine and running your first `pyscenic grn` + `ctx` analysis, from
zero. For a quick command reference once you're up and running, see the
[README](README.md).

## 0. Before you start

You'll need:
- A fresh Ubuntu (or Debian-based) machine or VM, with `sudo` access.
- Your own data: an expression matrix (`.loom`), a TF list (`.txt`), and
  cisTarget motif databases (`.feather` + `.tbl` files) for the TFs you
  want to analyze.

Don't have your own data yet? Skip to [step 7](#7-no-data-yet-try-the-smoke-test)
to try the whole pipeline with small, official reference files first.

## 1. Clone the repository

```bash
git clone https://github.com/PLeonLopes/scenic-pipeline-toolkit.git
cd scenic-pipeline-toolkit
```

## 2. Install pyscenic and pycistarget

```bash
bash scripts/install/install_pyscenic_pycistarget.sh
```

This takes a few minutes the first time (installs Conda/Mamba if missing,
then two separate environments). It's safe to run again if it's
interrupted — it picks up where it left off.

Confirm it worked:

```bash
bash scripts/install/verify_installation.sh
```

You should see `Summary: ALL OK.` at the end. If not, the output tells you
exactly which check failed — fix that before moving on.

From now on, open a new terminal (or run `source ~/.bashrc`) and activate
the environment before doing anything else:

```bash
conda activate scenic
```

## 3. Put your data somewhere the toolkit can find it

Create a folder (any name, anywhere) and put these inside it:
- Your `.loom` expression matrix.
- Your TF list `.txt` file (filename must contain "tfs", e.g. `hs_hgnc_tfs.txt`).
- One `.feather` + `.tbl` pair **per TF** you want to analyze (the two
  filenames need to share the TF's name — see `--help` on the next step if
  yours don't follow the default naming pattern).
- *(Optional)* one extra, generic `.feather` + `.tbl` pair (not tied to any
  single TF) if you also want a genome-wide baseline `ctx` run.

Example layout:

```
my_data/
├── my_expression.loom
├── my_tfs.txt
├── TF1.genes_vs_motifs.rankings.feather
├── TF1.tbl
├── TF2.genes_vs_motifs.rankings.feather
└── TF2.tbl
```

## 4. Generate your run configuration

This is the only "configuration" step — you never hand-write a CSV.

```bash
python scripts/generate_configs.py
```

Answer the prompts (press Enter to accept the default in `[brackets]`):

```
Folder with your data (loom, TF list, feather/tbl files): my_data
Project name (groups related runs under artifacts/<project>/, e.g. 'canonical_tfs'): my_project
Cell line (optional, e.g. 'HepG2'): HepG2
Run ID (short name for this experiment, e.g. 'my_experiment'): my_first_run
Number of grn replicates (grnboost2 is stochastic; run it several times for robustness) [1]:
Number of workers [4]:
NES threshold (used by ctx) [2.5]:
Dask mode (used by ctx) [dask_multiprocessing]:
GRN method (used by grn) [grnboost2]:
Output folder [artifacts/my_project/hepg2/outs]:
```

For a first try, just accept every default (press Enter each time) except
the data folder, project name, and run ID. At the end it prints what it
found and where it wrote the config — something like:

```
Found loom:          my_data/my_expression.loom
Found TF list:       my_data/my_tfs.txt
Found 2 TF(s) with both feather+tbl: TF1, TF2
Artifact folder:     artifacts/my_project/HepG2
Wrote artifacts/my_project/HepG2/configs/grn_runs_2026-01-01_10-30-00.local.csv (1 row(s), seed=1..1 for reproducibility)
Wrote artifacts/my_project/HepG2/configs/ctx_runs_2026-01-01_10-30-00.local.csv (2 rows)
```

`artifacts/<project>/[<cell-line>/]configs/` is a **stable** folder — every
time you run this, it adds a **new, timestamped file pair** there instead of
overwriting the previous one, so you can always look back at exactly what
config produced a given result. `logs/` and `outs/`, siblings of that
`configs/` folder, are where that project's logs and pyscenic outputs will
land once you run `grn`/`ctx` (see [step 8](#8-where-are-my-results)) —
everything about one project stays together. Use
`--project`/`--cell-line`/`--run-id` (and skip the prompts entirely) to
script this — see the [README](README.md#2-configuring-a-run).

If it complains it can't find your loom/TF list/feather/tbl files, double
check step 3 — the filenames need to follow the patterns described there.

## 5. Run `grn`

Step 4 printed the exact commands to run, under "Next steps" — copy the
first one, it looks like:

```bash
bash scripts/run_pyscenic_grn.sh artifacts/my_project/HepG2/configs/grn_runs_2026-01-01_10-30-00.local.csv
```

You'll see `pyscenic`'s own progress live on screen. This is the slowest
step — for a real dataset it can take from several minutes to hours,
depending on your data size and machine. When it's done, you'll see a
one-line summary per run and `[ OK ]` if everything went well.

## 6. Run `ctx`

Same idea, with the second command from step 4's "Next steps":

```bash
bash scripts/run_pyscenic_ctx.sh artifacts/my_project/HepG2/configs/ctx_runs_2026-01-01_10-30-00.local.csv
```

One run per TF (plus the baseline, if you have one). With the default
settings you'll see a live `[####] | 42% Completed` progress bar for each.

## 7. No data yet? Try the smoke test

Before you have your own files, you can validate the whole install using
small, official reference files instead:

```bash
bash scripts/tests/setup_real_smoke_test.sh
bash scripts/run_pyscenic_grn.sh artifacts/examples/grn_smoke_test.csv
bash scripts/run_pyscenic_ctx.sh artifacts/examples/ctx_smoke_test.csv
```

This downloads ~390MB the first time. It proves the pipeline runs
correctly end to end — it won't produce biologically meaningful results
(the expression data is random noise), just a working mechanical test.
Once you have real data, go back to [step 3](#3-put-your-data-somewhere-the-toolkit-can-find-it).

## 8. Where are my results?

Everything about one project/cell-line — the config you generated, what
happened when you ran it, and the results themselves — lives together
under one `artifacts/<project>/[<cell-line>/]` folder, split into three
sibling subfolders:

```
artifacts/my_project/hepg2/configs/grn_runs_*.local.csv           the config you generated (step 4)
artifacts/my_project/hepg2/configs/ctx_runs_*.local.csv

artifacts/my_project/hepg2/outs/adj/<run_id>.tsv                  one per grn run (the regulatory network)
artifacts/my_project/hepg2/outs/regs/<run_id>/reg_*.csv           one per ctx run (the regulons)

artifacts/my_project/hepg2/logs/<grn|ctx>_<run_id>.log            full output of that specific run
artifacts/my_project/hepg2/logs/<grn|ctx>_summary_*.csv           one row per run: status, timing, output size
artifacts/my_project/hepg2/logs/<grn|ctx>_<run_id>.meta.json      same info, structured, per run
```

Nothing lives in a separate global `outs/` or `logs/` folder — so opening
one project/cell-line folder shows you everything about it: what you
*asked for* (`configs/`), what *happened* (`logs/`), and what *came out*
(`outs/`).

## 9. Something failed — now what?

Look at the `status` column in the summary table printed at the end (also
saved to the `logs/` folder next to the config you ran — see
[step 8](#8-where-are-my-results)). The
[README](README.md#6-what-to-do-when-a-run-fails)
explains what each status means and which log file to check.

## 10. Ready to scale up?

Once a small run works end to end, you can:
- Point `--data-dir` at your real, full dataset.
- Add `--replicates 30` (or however many) to run `grn` multiple times for a
  robustness check — see the [README](README.md#2-configuring-a-run) for
  what that changes.
- Move to a proper server rather than a laptop — see the memory note in the
  README's [Notes](README.md#notes) section; a real TF list and dataset can
  need much more RAM than the quick tests above.