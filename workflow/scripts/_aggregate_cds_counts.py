#!/usr/bin/env python3
"""Merge per-sample featureCounts CDS tables into one matrix.

Writes the same layout as RIBOLD's ribold_cds_counts.tsv (gene_id, then one
column per sample) so the RNA-seq and Ribo-seq matrices can be joined on
gene_id for translation-efficiency calculations. The per-sample
featureCounts summaries are merged the same way (Status, then one column per
sample).

Pure Python on purpose: it runs anywhere python3 does.
"""

from __future__ import annotations

import argparse
import sys


def read_counts(path: str) -> dict[str, str]:
    """Return {gene_id: count} from a single-BAM featureCounts table."""
    counts: dict[str, str] = {}
    with open(path) as fh:
        header_seen = False
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if not header_seen:  # Geneid Chr Start End Strand Length <bam>
                header_seen = True
                if fields[0] != "Geneid" or len(fields) != 7:
                    raise ValueError(
                        f"{path}: not a single-sample featureCounts table"
                    )
                continue
            counts[fields[0]] = fields[6]
    if not header_seen:
        raise ValueError(f"{path}: no featureCounts header found")
    return counts


def read_summary(path: str) -> dict[str, str]:
    """Return {status: count} from a single-BAM featureCounts summary."""
    summary: dict[str, str] = {}
    with open(path) as fh:
        next(fh, None)  # Status <bam>
        for line in fh:
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 2:
                summary[fields[0]] = fields[1]
    return summary


def write_matrix(
    path: str, first_col: str, samples: list[str], tables: list[dict[str, str]]
) -> None:
    """Write rows in the first table's order; every table must have the same keys."""
    keys = list(tables[0])
    for sample, table in zip(samples, tables):
        if set(table) != set(keys):
            raise ValueError(
                f"sample '{sample}' has different {first_col} rows than '{samples[0]}'"
            )
    with open(path, "w") as out:
        out.write("\t".join([first_col] + samples) + "\n")
        for key in keys:
            out.write("\t".join([key] + [t[key] for t in tables]) + "\n")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--samples", required=True, help="comma-separated sample names")
    p.add_argument(
        "--counts",
        required=True,
        help="comma-separated featureCounts tables, in --samples order",
    )
    p.add_argument(
        "--summaries",
        required=True,
        help="comma-separated featureCounts summaries, in --samples order",
    )
    p.add_argument("--output_counts", required=True)
    p.add_argument("--output_summary", required=True)
    args = p.parse_args(argv)

    samples = args.samples.split(",")
    counts_files = args.counts.split(",")
    summary_files = args.summaries.split(",")
    if not (len(samples) == len(counts_files) == len(summary_files)):
        print(
            "ERROR: --samples, --counts and --summaries differ in length",
            file=sys.stderr,
        )
        return 1

    try:
        write_matrix(
            args.output_counts,
            "gene_id",
            samples,
            [read_counts(f) for f in counts_files],
        )
        write_matrix(
            args.output_summary,
            "Status",
            samples,
            [read_summary(f) for f in summary_files],
        )
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
