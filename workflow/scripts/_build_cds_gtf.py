#!/usr/bin/env python3
"""Build the GTF used for CDS-level counting (featureCounts -t CDS).

Host rows are copied as-is. Additive and viral GTFs in the shared fasta_gtf
folder usually have exon rows but no CDS rows, so their genes would be absent
from a CDS count matrix. For every non-host genome without any CDS row, each
exon row is followed by a CDS copy of itself (exon is taken as the ORF).
Non-host genomes that already carry CDS rows are copied unchanged.

Same exon-as-CDS convention as RIBOLD's _build_ref_gtf.py, so the HAROLD
(RNA-seq) and RIBOLD (Ribo-seq) CDS count matrices cover the same genes and
can be joined for translation-efficiency calculations. RIBOLD decides per
input GTF; here the composite ref.fixed.gtf already exists, so the genome of
each row is looked up from ref.fa.regions (genome <tab> space-separated
sequence names) instead.

Pure Python on purpose: it runs anywhere python3 does.
"""

from __future__ import annotations

import argparse
import sys


def parse_regions(path: str) -> dict[str, str]:
    """Return {sequence name: genome name} from a ref.fa.regions file."""
    seq_to_genome: dict[str, str] = {}
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if not parts:
                continue
            for seq in parts[1:]:
                seq_to_genome[seq] = parts[0]
    return seq_to_genome


def _rows(path: str):
    """Yield (line, fields) for non-comment GTF rows."""
    with open(path) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                continue
            yield line.rstrip("\n"), fields


def genomes_with_cds(gtf: str, seq_to_genome: dict[str, str]) -> set[str]:
    """Genomes that have at least one CDS row in the GTF."""
    return {
        seq_to_genome[fields[0]]
        for _, fields in _rows(gtf)
        if fields[2] == "CDS" and fields[0] in seq_to_genome
    }


def write_gtf(
    gtf: str, out, seq_to_genome: dict[str, str], hosts: set[str]
) -> dict[str, int]:
    """Copy GTF rows to out, adding exon-as-CDS rows; return {genome: CDS rows added}."""
    keep_as_is = genomes_with_cds(gtf, seq_to_genome) | hosts
    added: dict[str, int] = {}
    for line, fields in _rows(gtf):
        out.write(line + "\n")
        # sequences missing from the regions file are left alone
        genome = seq_to_genome.get(fields[0])
        if genome is None or genome in keep_as_is or fields[2] != "exon":
            continue
        cds = fields.copy()
        cds[2] = "CDS"
        cds[7] = "0" if cds[7] == "." else cds[7]
        out.write("\t".join(cds) + "\n")
        added[genome] = added.get(genome, 0) + 1
    return added


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--ingtf", required=True, help="composite GTF (ref.fixed.gtf)")
    p.add_argument("--regions", required=True, help="ref.fa.regions")
    p.add_argument(
        "--host",
        default="",
        help="comma-separated host genome name(s); never given exon-as-CDS rows",
    )
    p.add_argument("--outgtf", required=True)
    args = p.parse_args(argv)

    seq_to_genome = parse_regions(args.regions)
    hosts = {h for h in args.host.replace(" ", "").split(",") if h}
    with open(args.outgtf, "w") as out:
        added = write_gtf(args.ingtf, out, seq_to_genome, hosts)
    for genome, n in added.items():
        print(f"{genome}: added {n} CDS rows from exons")
    if not added:
        print("no CDS rows added")
    return 0


if __name__ == "__main__":
    sys.exit(main())
