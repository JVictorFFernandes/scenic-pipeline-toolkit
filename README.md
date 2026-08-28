# scenic-pipeline-toolkit

Installation and automation toolkit to run analyses with
[pySCENIC](https://github.com/aertslab/pySCENIC) and
[pycistarget](https://github.com/aertslab/pycistarget) on an Ubuntu server,
without editing bash for every new replicate/TF/cell line.

The goal is to be **dataset-agnostic**: the CSVs in `configs/` point to the
paths of your own files (`.loom`, `.tbl`, `.feather`, TF list), so the same
pipeline works for HepG2, another cell line, or any new experiment — only
the CSV content changes. The examples in this README use HepG2 just to
illustrate the format.

## 1. Installation (once, on the server)

```bash
bash install/install_pyscenic_pycistarget.sh
```

This installs system dependencies, Conda/Mamba (Miniforge) if not already
present, and creates **two separate conda environments**:

- `scenic` (Python 3.10) — `pyscenic` only. This is what
  `scripts/run_pyscenic_grn.sh` and `scripts/run_pyscenic_ctx.sh` use.
- `pycistarget` (Python 3.11) — `pycistarget` only.

Why two environments? `pyscenic` (via `dask`) requires `pandas>=2.0`, while
`pycistarget` pulls in a dependency (`pyranges`) that requires `pandas<2.0`.
Installing both together makes one break the other — this is a real, known
conflict in this ecosystem, not an arbitrary choice. Since the `grn`/`ctx`
scripts don't use `pycistarget`, this doesn't change anything for people who
only run those two analyses.

The script can be run again without issue — it skips any step that's
already done.

Then, confirm everything is fine:

```bash
bash install/verify_installation.sh
```

This should end with `Summary: ALL OK.`. If something fails, the output
itself tells you which check failed (the `pyscenic` command, some Python
`import`, etc.) — copy the message to ask for help.

In every new terminal session, before running the `grn`/`ctx` scripts:

```bash
conda activate scenic
```

To work with `pycistarget`, use the other environment:

```bash
conda activate pycistarget
```

## 2. Running `pyscenic grn`

1. Edit `configs/grn_runs.csv`. Each row is one run:

   ```
   run_id,loom_path,tfs_path,output_path,num_workers,method
   Hepg2_n43,data/Hepg2_GSM5677000_filtered_scenic.loom,downloads/hs_hgnc_tfs.txt,outs/adj_Hepg2_n43.tsv,6,grnboost2
   ```

   - `run_id`: any name, just used to identify the row in logs/summary.
   - `output_path`: if the file already exists, the run is **skipped**
     automatically (so you can rerun the whole CSV without redoing work
     that's already done).

2. Run:

   ```bash
   bash scripts/run_pyscenic_grn.sh
   ```

   Or, to use a different CSV: `bash scripts/run_pyscenic_grn.sh configs/other.csv`

3. At the end, the script prints a summary table (`OK` / `FAIL_*` /
   `SKIPPED` per row) and saves it to `logs/grn_summary_<date>.csv`. The
   full log for each run is in `logs/grn_<run_id>.log`.

## 3. Running `pyscenic ctx`

Same idea, editing `configs/ctx_runs.csv` (one row per TF/run) and running:

```bash
bash scripts/run_pyscenic_ctx.sh
```

Summary in `logs/ctx_summary_<date>.csv`, individual log in
`logs/ctx_<run_id>.log`.

## 4. Testing without actually running (`--dry-run`)

Before launching a long run, you can check that all the CSV paths exist and
see the exact command that would be executed, without actually calling
`pyscenic`:

```bash
bash scripts/run_pyscenic_grn.sh --dry-run
bash scripts/run_pyscenic_ctx.sh --dry-run
```

## 5. Reprocessing something that already ran

By default, if `output_path` already exists the row is skipped
(`SKIPPED`). To force reprocessing (e.g. you changed a parameter and want
to redo everything):

```bash
bash scripts/run_pyscenic_grn.sh --force
```

## 6. What to do when a run fails

The final summary shows the `status` of each row:

| status        | meaning                                                              |
|---------------|-----------------------------------------------------------------------|
| `OK`          | ran and the output file passed validation                            |
| `SKIPPED`     | output already existed, was not redone                               |
| `FAIL_INPUT`  | some input file in the CSV doesn't exist or is empty                 |
| `FAIL_RUN`    | the `pyscenic` command exited with an error — see the log in `logs/` |
| `FAIL_OUTPUT` | the command ran but the output was empty or missing expected columns |

For any `FAIL_*`, open the corresponding log file (`logs/grn_<run_id>.log`
or `logs/ctx_<run_id>.log`) — it has the full stdout/stderr from `pyscenic`
for that specific run.

## 7. Smoke test with real AERTSLAB files (optional)

Before running with your real experiment data, you can validate the whole
installation (grn + ctx) using the official cisTarget databases (downloaded
from [resources.aertslab.org](https://resources.aertslab.org/)) and a
synthetic dataset with real genes/TFs extracted from those databases:

```bash
conda activate scenic
bash scripts/tests/setup_real_smoke_test.sh
bash scripts/run_pyscenic_grn.sh configs/grn_smoke_test.csv
bash scripts/run_pyscenic_ctx.sh configs/ctx_smoke_test.csv
```

This downloads ~390MB (hg38 rankings database + motif annotation table) the
first time. Since the generated expression is random noise, this validates
that the *pipeline runs* with real files in the correct format — not that
the regulons found make biological sense (that requires real scRNA-seq
data).

## Project structure

```
install/             installation scripts (pyscenic + pycistarget)
scripts/              generic grn/ctx scripts + lib/common.sh
scripts/tests/         smoke-test-only scripts (not part of a real run)
configs/              per-run configuration CSVs (see below)
data/, downloads/     input data (not versioned, see .gitignore)
outs/, logs/          run outputs and logs (not versioned)
```

### What is `configs/` for?

Each CSV in `configs/` is a **run plan**: one row = one `pyscenic grn` or
`pyscenic ctx` execution, with all its parameters (input paths, output
path, number of workers, thresholds, etc.) as columns. Instead of copying
and editing a bash command for every new replicate, TF, or cell line, you
just add a row to the CSV — the generic scripts (`run_pyscenic_grn.sh`,
`run_pyscenic_ctx.sh`) read the file and run each row with validation,
logging, and a final summary.

- `configs/grn_runs.csv` / `configs/ctx_runs.csv` — the real templates for
  your experiments (currently filled with the HepG2 example; replace the
  paths with your own data/cell line).
- `configs/grn_smoke_test.csv` / `configs/ctx_smoke_test.csv` — generated
  automatically by `scripts/tests/setup_real_smoke_test.sh`, only used for
  the smoke test in section 7.

## Notes

- The original example scripts (`run_pyscenic_grn.sh` and
  `run_pyscenic_ctx_pioneiros.sh`, at the project root) remain here as a
  reference for what the CSVs in `configs/` reproduce.
- This project assumes the input data (`.loom`, `.feather`, `.tbl`, TF
  list) is already downloaded locally on the server — the installation
  script doesn't download motif databases, only the software.
- `pyscenic` and `pycistarget` have incompatible transitive dependencies
  (see section 1) — that's why they live in separate conda environments
  (`scenic` and `pycistarget`). Never run `pip install pycistarget` inside
  the `scenic` environment; if that happens by accident, the simplest fix
  is to delete and recreate the environment: `conda env remove -n scenic -y`
  and run `install/install_pyscenic_pycistarget.sh` again.
- `pyscenic 0.12.1` (2022) uses `np.object`/`np.bool`/`np.int` directly in
  its source code — aliases that NumPy removed in version 1.24 (Dec/2022).
  That's why the script pins `numpy==1.23.5` + `numba==0.56.4` +
  `llvmlite==0.39.1` in the `scenic` environment. Don't run
  `pip install --upgrade numpy` (or anything that forces a newer numpy) in
  that environment — it breaks `pyscenic` again.
- `pyscenic grn` (via `arboreto`) calls a dask function with an empty list
  by default — "classic" dask tolerated this, but starting from version
  2024.03.0 (new `dask-expr` backend) this became an error (`Must supply at
  least one delayed object`). That's why the script pins
  `dask==2023.5.0` + `distributed==2023.5.0`. Same rule: don't manually
  upgrade dask in that environment.
