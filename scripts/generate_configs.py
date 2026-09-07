#!/usr/bin/env python
"""
Writes configs/grn_runs.local.csv and configs/ctx_runs.local.csv
automatically, instead of hand-writing CSV rows for every TF.

Run once per experiment/data drop. Two ways to use it:

  Interactive (no arguments) — asks for each value, with sensible defaults
  you can accept by just pressing Enter:

    python scripts/generate_configs.py

  Non-interactive (pass --data-dir) — for scripting/automation/repeat runs,
  skips all prompts:

    python scripts/generate_configs.py --data-dir my_data --run-id my_experiment --num-workers 4

What it looks for inside the data folder (recursively):
  - one .loom file                          -> expression matrix
  - one TF list file matching *tfs*.txt     -> candidate regulators for grn
  - .feather files matching --feather-regex -> one per TF, for ctx
  - .tbl files matching --tbl-regex         -> one per TF, for ctx

A TF is included in ctx_runs.local.csv only if BOTH its .feather and its
.tbl file were found; TFs with only one of the two are skipped with a
warning (nothing silently wrong is written).

If exactly one extra .feather/.tbl pair is found that does NOT match a TF
(a plain, genome-wide cisTarget database, not tied to any single TF), it's
added as one extra "motifs_only" baseline row per replicate, run before the
per-TF rows — pass --no-baseline to skip this even if such a pair exists.

Pass --replicates N (default 1) to run grn N independent times (grnboost2
has no fixed random seed, so each run naturally differs) and cross each
replicate's adjacency with every TF for ctx — e.g. --replicates 30 with 14
TFs writes 30 grn rows and 30*14=420 ctx rows.

The generated *.local.csv files are the ones scripts/run_pyscenic_grn.sh and
scripts/run_pyscenic_ctx.sh use by default, and are gitignored — they hold
real, machine-specific paths and are never meant to be committed. The
*.example.csv files in configs/ are the tracked, safe-to-share templates.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

DEFAULT_FEATHER_REGEX = r"motifs_plus_([A-Za-z0-9]+)\.genes_vs_motifs\.rankings\.feather$"
DEFAULT_TBL_REGEX = r"pptf_([A-Za-z0-9]+)\.tbl$"
DEFAULT_TFS_GLOB = "*tfs*.txt"


def ask(question: str, default: str | None = None, validate=None) -> str:
    """Prompt the user for a value, showing `default` (used if they just
    press Enter). Re-prompts if `validate(value)` returns an error string."""
    suffix = f" [{default}]" if default is not None else ""
    while True:
        answer = input(f"{question}{suffix}: ").strip()
        if not answer:
            if default is not None:
                answer = default
            else:
                print("  This value is required, please enter something.")
                continue
        if validate:
            error = validate(answer)
            if error:
                print(f"  {error}")
                continue
        return answer


def run_interactive() -> argparse.Namespace:
    print("=== scenic-pipeline-toolkit: interactive config setup ===")
    print("Press Enter to accept the default shown in [brackets].\n")

    data_dir = ask(
        "Folder with your data (loom, TF list, feather/tbl files)",
        validate=lambda v: None if Path(v).is_dir() else f"'{v}' is not a directory, try again.",
    )
    run_id = ask("Run ID (short name for this experiment, e.g. 'my_experiment')")
    replicates = ask(
        "Number of grn replicates (grnboost2 is stochastic; run it several times for robustness)",
        default="1",
        validate=lambda v: None if v.isdigit() and int(v) > 0 else "Must be a positive integer.",
    )
    num_workers = ask(
        "Number of workers",
        default="4",
        validate=lambda v: None if v.isdigit() and int(v) > 0 else "Must be a positive integer.",
    )
    nes_threshold = ask("NES threshold (used by ctx)", default="2.5")
    mode = ask("Dask mode (used by ctx)", default="dask_multiprocessing")
    method = ask("GRN method (used by grn)", default="grnboost2")
    outs_dir = ask("Output folder", default="outs")

    return argparse.Namespace(
        data_dir=data_dir,
        run_id=run_id,
        replicates=int(replicates),
        no_seed=False,
        num_workers=int(num_workers),
        nes_threshold=nes_threshold,
        mode=mode,
        method=method,
        outs_dir=outs_dir,
        loom=None,
        tfs=None,
        baseline_feather=None,
        baseline_tbl=None,
        no_baseline=False,
        feather_regex=DEFAULT_FEATHER_REGEX,
        tbl_regex=DEFAULT_TBL_REGEX,
        grn_csv="configs/grn_runs.local.csv",
        ctx_csv="configs/ctx_runs.local.csv",
    )


def find_one(data_dir: Path, pattern: str, kind: str, override: str | None) -> Path:
    if override:
        path = Path(override)
        if not path.is_file():
            sys.exit(f"ERROR: --{kind.lower().replace(' ', '-')} points to a file that doesn't exist: {path}")
        return path

    matches = sorted(data_dir.rglob(pattern))
    if len(matches) == 1:
        return matches[0]
    if len(matches) == 0:
        sys.exit(
            f"ERROR: no {kind} found under {data_dir} (looked for '{pattern}'). "
            f"Pass it explicitly with the matching flag."
        )
    sys.exit(
        f"ERROR: found {len(matches)} possible {kind} files under {data_dir}, expected exactly one:\n  "
        + "\n  ".join(str(m) for m in matches)
        + "\nPass the right one explicitly with the matching flag."
    )


def find_tf_files(data_dir: Path, extension: str, regex: str) -> dict[str, Path]:
    pattern = re.compile(regex)
    found: dict[str, Path] = {}
    for path in sorted(data_dir.rglob(f"*.{extension}")):
        m = pattern.search(path.name)
        if m:
            found[m.group(1)] = path
    return found


def find_baseline(data_dir: Path, extension: str, matched: set[Path], kind: str, override: str | None) -> Path | None:
    """Finds the plain, genome-wide feather/tbl (the one that ISN'T one of
    the per-TF files already matched by find_tf_files). Returns None if
    there isn't exactly one such file and no override was given — a
    baseline row is optional, so this never exits the program."""
    if override:
        path = Path(override)
        if not path.is_file():
            sys.exit(f"ERROR: --{kind} points to a file that doesn't exist: {path}")
        return path

    candidates = [p for p in sorted(data_dir.rglob(f"*.{extension}")) if p not in matched]
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        print(
            f"WARNING: found {len(candidates)} .{extension} file(s) that aren't tied to any TF, "
            f"expected at most one for the 'motifs_only' baseline — skipping it. "
            f"Pass --{kind} to pick one explicitly:\n  " + "\n  ".join(str(c) for c in candidates),
            file=sys.stderr,
        )
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--data-dir",
        help="folder to scan for loom/TF-list/feather/tbl files. "
        "Omit this (and every other flag) to be prompted interactively instead.",
    )
    parser.add_argument("--run-id", help="short name for this experiment, e.g. 'my_experiment'")
    parser.add_argument(
        "--replicates",
        type=int,
        default=1,
        help="number of independent grn runs (default: 1). Each replicate is crossed with every TF for ctx.",
    )
    parser.add_argument(
        "--no-seed",
        action="store_true",
        help="don't assign a --seed to grn (default: replicate i gets seed=i, so runs are reproducible "
        "while still being independent of each other; pass this to get pyscenic's own random-seed-per-run default instead).",
    )
    parser.add_argument("--num-workers", type=int, default=4, help="--num_workers for both grn and ctx (default: 4)")
    parser.add_argument("--nes-threshold", default="2.5", help="--nes_threshold for ctx (default: 2.5)")
    parser.add_argument("--mode", default="dask_multiprocessing", help="--mode for ctx (default: dask_multiprocessing)")
    parser.add_argument("--method", default="grnboost2", help="--method for grn (default: grnboost2)")
    parser.add_argument("--outs-dir", default="outs", help="base output folder (default: outs)")
    parser.add_argument("--loom", help="override: exact path to the .loom file (skip auto-discovery)")
    parser.add_argument("--tfs", help="override: exact path to the TF list .txt file (skip auto-discovery)")
    parser.add_argument("--baseline-feather", help="override: exact path to the genome-wide, non-per-TF .feather (skip auto-discovery)")
    parser.add_argument("--baseline-tbl", help="override: exact path to the genome-wide, non-per-TF .tbl (skip auto-discovery)")
    parser.add_argument(
        "--no-baseline",
        action="store_true",
        help="don't add a 'motifs_only' baseline row, even if a genome-wide feather+tbl pair is found",
    )
    parser.add_argument(
        "--feather-regex",
        default=DEFAULT_FEATHER_REGEX,
        help=r"regex with one capture group for the TF name, applied to .feather filenames "
        rf"(default: {DEFAULT_FEATHER_REGEX!r})",
    )
    parser.add_argument(
        "--tbl-regex",
        default=DEFAULT_TBL_REGEX,
        help=rf"regex with one capture group for the TF name, applied to .tbl filenames (default: {DEFAULT_TBL_REGEX!r})",
    )
    parser.add_argument("--grn-csv", default="configs/grn_runs.local.csv", help="output path for the grn CSV")
    parser.add_argument("--ctx-csv", default="configs/ctx_runs.local.csv", help="output path for the ctx CSV")
    args = parser.parse_args()

    if args.data_dir is None:
        if not sys.stdin.isatty():
            parser.error("--data-dir is required when not running in an interactive terminal.")
        args = run_interactive()
    elif args.run_id is None:
        parser.error("--run-id is required (or omit --data-dir too, to use interactive mode).")

    if args.replicates < 1:
        parser.error("--replicates must be a positive integer.")

    return args


def replicate_run_ids(run_id: str, replicates: int) -> list[str]:
    """Returns the run_id for each replicate. With replicates=1, the plain
    run_id is used unchanged (so single-replicate output filenames don't
    change); with more, each gets a zero-padded '_repNN' suffix."""
    if replicates == 1:
        return [run_id]
    width = max(2, len(str(replicates)))
    return [f"{run_id}_rep{i:0{width}d}" for i in range(1, replicates + 1)]


def main():
    args = parse_args()

    data_dir = Path(args.data_dir)
    if not data_dir.is_dir():
        sys.exit(f"ERROR: --data-dir is not a directory: {data_dir}")

    loom_path = find_one(data_dir, "*.loom", "loom", args.loom)
    tfs_path = find_one(data_dir, DEFAULT_TFS_GLOB, "TF list", args.tfs)

    feather_by_tf = find_tf_files(data_dir, "feather", args.feather_regex)
    tbl_by_tf = find_tf_files(data_dir, "tbl", args.tbl_regex)

    tfs_with_both = sorted(set(feather_by_tf) & set(tbl_by_tf))
    feather_only = sorted(set(feather_by_tf) - set(tbl_by_tf))
    tbl_only = sorted(set(tbl_by_tf) - set(feather_by_tf))

    if feather_only:
        print(f"WARNING: {len(feather_only)} TF(s) have a .feather but no matching .tbl, skipping: {', '.join(feather_only)}", file=sys.stderr)
    if tbl_only:
        print(f"WARNING: {len(tbl_only)} TF(s) have a .tbl but no matching .feather, skipping: {', '.join(tbl_only)}", file=sys.stderr)
    if not tfs_with_both:
        sys.exit("ERROR: no TF has both a .feather and a .tbl file — nothing to write to ctx_runs.local.csv.")

    baseline_feather = None
    baseline_tbl = None
    if not args.no_baseline:
        baseline_feather = find_baseline(data_dir, "feather", set(feather_by_tf.values()), "baseline-feather", args.baseline_feather)
        baseline_tbl = find_baseline(data_dir, "tbl", set(tbl_by_tf.values()), "baseline-tbl", args.baseline_tbl)
        if baseline_feather and not baseline_tbl:
            print(f"WARNING: found a baseline .feather ({baseline_feather}) but no baseline .tbl — skipping the 'motifs_only' row.", file=sys.stderr)
            baseline_feather = None
        elif baseline_tbl and not baseline_feather:
            print(f"WARNING: found a baseline .tbl ({baseline_tbl}) but no baseline .feather — skipping the 'motifs_only' row.", file=sys.stderr)
            baseline_tbl = None

    print(f"\nFound loom:          {loom_path}")
    print(f"Found TF list:       {tfs_path}")
    print(f"Found {len(tfs_with_both)} TF(s) with both feather+tbl: {', '.join(tfs_with_both)}")
    if baseline_feather:
        print(f"Found baseline (motifs_only) feather+tbl: {baseline_feather.name} + {baseline_tbl.name}")

    rep_ids = replicate_run_ids(args.run_id, args.replicates)
    if args.replicates > 1:
        print(f"Generating {args.replicates} grn replicate(s): {', '.join(rep_ids)}")

    grn_csv_path = Path(args.grn_csv)
    grn_csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(grn_csv_path, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["run_id", "loom_path", "tfs_path", "output_path", "num_workers", "method", "seed"])
        for i, rep_id in enumerate(rep_ids, start=1):
            grn_output = f"{args.outs_dir}/adj/{rep_id}.tsv"
            seed = "" if args.no_seed else i
            writer.writerow([rep_id, loom_path, tfs_path, grn_output, args.num_workers, args.method, seed])
    if args.no_seed:
        print(f"Wrote {grn_csv_path} ({len(rep_ids)} row(s), no seed — each run will use pyscenic's own random seed)")
    else:
        print(f"Wrote {grn_csv_path} ({len(rep_ids)} row(s), seed=1..{len(rep_ids)} for reproducibility)")

    ctx_csv_path = Path(args.ctx_csv)
    ctx_csv_path.parent.mkdir(parents=True, exist_ok=True)
    n_ctx_rows = 0
    with open(ctx_csv_path, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(
            ["run_id", "tf_name", "adj_path", "feather_path", "tbl_path", "loom_path", "nes_threshold", "mode", "num_workers", "output_path"]
        )
        for rep_id in rep_ids:
            grn_output = f"{args.outs_dir}/adj/{rep_id}.tsv"

            if baseline_feather:
                row_id = f"{rep_id}_motifs_only"
                output_path = f"{args.outs_dir}/regs/{rep_id}/reg_motifs_only.csv"
                writer.writerow(
                    [row_id, "ALL", grn_output, baseline_feather, baseline_tbl, loom_path, args.nes_threshold, args.mode, args.num_workers, output_path]
                )
                n_ctx_rows += 1

            for tf in tfs_with_both:
                row_id = f"{rep_id}_{tf}"
                output_path = f"{args.outs_dir}/regs/{rep_id}/reg_{tf}.csv"
                writer.writerow(
                    [row_id, tf, grn_output, feather_by_tf[tf], tbl_by_tf[tf], loom_path, args.nes_threshold, args.mode, args.num_workers, output_path]
                )
                n_ctx_rows += 1
    print(f"Wrote {ctx_csv_path} ({n_ctx_rows} rows)")

    print()
    print("Next steps:")
    print(f"    bash scripts/run_pyscenic_grn.sh {grn_csv_path}")
    print(f"    bash scripts/run_pyscenic_ctx.sh {ctx_csv_path}")


if __name__ == "__main__":
    main()
