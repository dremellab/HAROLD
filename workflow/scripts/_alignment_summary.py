#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

import pysam


STAR_METRIC_PATTERNS = {
    "uniquely_mapped_reads": "Uniquely mapped reads number",
    "multi_mapped_reads": "Number of reads mapped to multiple loci",
    "too_many_loci_reads": "Number of reads mapped to too many loci",
    "unmapped_too_many_mismatches": "Number of reads unmapped: too many mismatches",
    "unmapped_too_short": "Number of reads unmapped: too short",
    "unmapped_other": "Number of reads unmapped: other",
}


def read_regions_file(path: Path) -> dict[str, set[str]]:
    genomes: dict[str, set[str]] = {}
    if not path.exists():
        return genomes
    with path.open() as handle:
        for line in handle:
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            genomes.setdefault(parts[0], set()).update(parts[1:])
    return genomes


def parse_cutadapt_report(path: Path) -> dict[str, int | str]:
    metrics: dict[str, int | str] = {
        "library_type": "NA",
        "total_reads": "NA",
        "trimmed_reads": "NA",
    }
    patterns = {
        "Total read pairs processed:": ("PE", "total_reads"),
        "Pairs written (passing filters):": ("PE", "trimmed_reads"),
        "Total reads processed:": ("SE", "total_reads"),
        "Reads written (passing filters):": ("SE", "trimmed_reads"),
    }

    with path.open() as handle:
        for raw_line in handle:
            line = raw_line.strip()
            for prefix, (library_type, key) in patterns.items():
                if not line.startswith(prefix):
                    continue
                match = re.search(r"([\d,]+)", line)
                if match:
                    metrics["library_type"] = library_type
                    value = int(match.group(1).replace(",", ""))
                    metrics[key] = value * 2 if library_type == "PE" else value
                break

    return metrics


def parse_fastqvalidator_report(path: Path) -> int | str:
    pattern = re.compile(r"with\s+\d+\s+lines containing\s+([\d,]+)\s+sequences\.")
    total_sequences = 0
    seen = False
    with path.open() as handle:
        for raw_line in handle:
            match = pattern.search(raw_line.strip())
            if not match:
                continue
            sequences = int(match.group(1).replace(",", ""))
            total_sequences += sequences
            seen = True
    return total_sequences if seen else "NA"


def parse_star_log(path: Path) -> dict[str, int | str]:
    metrics: dict[str, int | str] = {key: "NA" for key in STAR_METRIC_PATTERNS}
    with path.open() as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if "|" not in line:
                continue
            key, value = [item.strip() for item in line.split("|", 1)]
            for metric_key, label in STAR_METRIC_PATTERNS.items():
                if key != label:
                    continue
                value_clean = value.replace(",", "")
                try:
                    metrics[metric_key] = int(value_clean)
                except ValueError:
                    metrics[metric_key] = "NA"
                break

    mapped_parts = [
        metrics["uniquely_mapped_reads"],
        metrics["multi_mapped_reads"],
        metrics["too_many_loci_reads"],
    ]
    if all(isinstance(value, int) for value in mapped_parts):
        metrics["reads_mapped_to_assembly"] = sum(mapped_parts)
    else:
        metrics["reads_mapped_to_assembly"] = "NA"
    return metrics


def count_primary_alignments_by_contig(path: Path) -> dict[str, int]:
    mapped_by_contig: dict[str, int] = {}
    with pysam.AlignmentFile(path, "rb") as bam:
        for read in bam.fetch(until_eof=True):
            if read.is_unmapped or read.is_secondary or read.is_supplementary:
                continue
            contig = bam.get_reference_name(read.reference_id)
            mapped_by_contig[contig] = mapped_by_contig.get(contig, 0) + 1
    return mapped_by_contig


def sum_contigs(mapped_by_contig: dict[str, int], contigs: set[str]) -> int:
    return sum(mapped_by_contig.get(contig, 0) for contig in contigs)


def int_or_na(value: int | str) -> str:
    return str(value) if isinstance(value, int) else "NA"


def scale_star_metrics_for_library_type(
    metrics: dict[str, int | str], library_type: str
) -> dict[str, int | str]:
    if library_type != "PE":
        return metrics

    scaled = dict(metrics)
    for key in (
        "reads_mapped_to_assembly",
        "uniquely_mapped_reads",
        "multi_mapped_reads",
        "too_many_loci_reads",
    ):
        value = scaled.get(key)
        if isinstance(value, int):
            scaled[key] = value * 2
    return scaled


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create centralized alignment summary TSV for HAROLD."
    )
    parser.add_argument("--results-dir", required=True)
    parser.add_argument("--regions-host", required=True)
    parser.add_argument("--regions-viruses", required=True)
    parser.add_argument("--regions-additives", required=True)
    parser.add_argument("--output", default="-")
    parser.add_argument("--chrr-names", default="chrR")
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    if not results_dir.exists():
        print(f"ERROR: results dir not found: {results_dir}", file=sys.stderr)
        return 2

    host_genomes = read_regions_file(Path(args.regions_host))
    virus_genomes = read_regions_file(Path(args.regions_viruses))
    additive_genomes = read_regions_file(Path(args.regions_additives))

    host_contigs: set[str] = set()
    for contigs in host_genomes.values():
        host_contigs.update(contigs)

    chrr_contigs = {item.strip() for item in args.chrr_names.split(",") if item.strip()}
    virus_names = sorted(virus_genomes)
    additive_names = sorted(additive_genomes)

    rows: list[dict[str, str]] = []
    sample_dirs = sorted(path for path in results_dir.iterdir() if path.is_dir())
    for sample_dir in sample_dirs:
        sample = sample_dir.name
        cutadapt_report = sample_dir / "trim" / f"{sample}.cutadapt.report.txt"
        fastqvalidator_report = (
            sample_dir / "fastq_validation" / f"{sample}.fastq_validator.txt"
        )
        star_log = sample_dir / "STAR" / f"{sample}.Log.final.out"
        bam = sample_dir / "STAR" / f"{sample}.Aligned.sortedByCoord.out.bam"

        if (
            not cutadapt_report.exists()
            or not fastqvalidator_report.exists()
            or not star_log.exists()
            or not bam.exists()
        ):
            continue

        cutadapt_metrics = parse_cutadapt_report(cutadapt_report)
        raw_reads = parse_fastqvalidator_report(fastqvalidator_report)
        star_metrics = parse_star_log(star_log)
        star_metrics = scale_star_metrics_for_library_type(
            star_metrics, str(cutadapt_metrics["library_type"])
        )
        mapped_by_contig = count_primary_alignments_by_contig(bam)

        chrr_mapped = sum_contigs(mapped_by_contig, chrr_contigs)
        host_total_mapped = sum_contigs(mapped_by_contig, host_contigs)
        host_mapped = (
            host_total_mapped - chrr_mapped
            if host_total_mapped >= chrr_mapped
            else host_total_mapped
        )

        row = {
            "sample": sample,
            "library_type": str(cutadapt_metrics["library_type"]),
            "total_reads": int_or_na(raw_reads),
            "trimmed_reads": int_or_na(cutadapt_metrics["trimmed_reads"]),
            "reads_mapped_to_assembly": int_or_na(
                star_metrics["reads_mapped_to_assembly"]
            ),
            "uniquely_mapped_reads": int_or_na(
                star_metrics["uniquely_mapped_reads"]
            ),
            "multi_mapped_reads": int_or_na(star_metrics["multi_mapped_reads"]),
            "too_many_loci_reads": int_or_na(star_metrics["too_many_loci_reads"]),
            "host_mapped": str(host_mapped),
            "chrR_mapped": str(chrr_mapped),
        }
        for virus in virus_names:
            row[f"{virus}_mapped"] = str(
                sum_contigs(mapped_by_contig, virus_genomes[virus])
            )
        for additive in additive_names:
            row[f"{additive}_mapped"] = str(
                sum_contigs(mapped_by_contig, additive_genomes[additive])
            )
        rows.append(row)

    fieldnames = [
        "sample",
        "library_type",
        "total_reads",
        "trimmed_reads",
        "reads_mapped_to_assembly",
        "uniquely_mapped_reads",
        "multi_mapped_reads",
        "too_many_loci_reads",
        "host_mapped",
        "chrR_mapped",
    ]
    fieldnames.extend(f"{virus}_mapped" for virus in virus_names)
    fieldnames.extend(f"{additive}_mapped" for additive in additive_names)

    if args.output == "-":
        handle = sys.stdout
        close_handle = False
    else:
        handle = open(args.output, "w", newline="")
        close_handle = True

    try:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    finally:
        if close_handle:
            handle.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
