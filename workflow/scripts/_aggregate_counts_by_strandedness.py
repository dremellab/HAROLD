#!/usr/bin/env python3
import os
import sys
import pandas as pd
import re
from collections import defaultdict
import argparse


def infer_strandedness(file_path, fraction_threshold=0.8):
    """
    Returns (strand, inference_fraction)
    strand ∈ {forward, reverse, unstranded}
    inference_fraction = fraction value used to decide
    """
    with open(file_path) as f:
        content = f.read()
    if "Fraction of reads explained by" not in content:
        return "unstranded", 0.0

    match = re.findall(r"Fraction of reads explained by \"(.*?)\": (\d+\.\d+)", content)
    if not match:
        return "unstranded", 0.0

    fractions = {read_type: float(value) for read_type, value in match}

    # Paired-end case
    if "1+-,1-+,2++,2--" in fractions:
        frac = fractions.get("1+-,1-+,2++,2--", 0.5)
        if frac > fraction_threshold:
            return "reverse", frac
        elif frac < (1 - fraction_threshold):
            return "forward", frac
        else:
            return "unstranded", frac

    # Single-end case
    if "+-,-+" in fractions:
        frac = fractions.get("+-,-+", 0.5)
        if frac > fraction_threshold:
            return "reverse", frac
        elif frac < (1 - fraction_threshold):
            return "forward", frac
        else:
            return "unstranded", frac

    return "unstranded", 0.0


def parse_gtf_lookup(gtf_file):
    lookup = {}
    gene_transcripts = defaultdict(lambda: defaultdict(list))

    with open(gtf_file) as f:
        for line in f:
            if line.startswith("#"):
                continue
            parts = line.strip().split("\t")
            if len(parts) < 9:
                continue
            (
                chrom,
                source,
                feature_type,
                start,
                end,
                score,
                strand,
                frame,
                attr_str,
            ) = parts
            attributes = {}
            for attr in attr_str.strip().split(";"):
                if attr.strip():
                    key, val = attr.strip().split(" ", 1)
                    attributes[key] = val.strip('"')
            gene_id = attributes.get("gene_id")
            transcript_id = attributes.get("transcript_id")
            gene_name = attributes.get("gene_name", "NA")
            gene_type = attributes.get("gene_type", "NA")

            if feature_type == "exon" and gene_id and transcript_id:
                start, end = int(start), int(end)
                gene_transcripts[gene_id][transcript_id].append((start, end))

            if feature_type == "gene" and gene_id:
                lookup[gene_id] = {
                    "gene_id": gene_id,
                    "gene_name": gene_name,
                    "gene_chr": chrom,
                    "gene_start": int(start),
                    "gene_end": int(end),
                    "gene_strand": strand,
                    "gene_type": gene_type,
                }

    for gene_id, transcripts in gene_transcripts.items():
        longest = 0
        for exons in transcripts.values():
            sorted_exons = sorted(exons)
            merged = [sorted_exons[0]]
            for current in sorted_exons[1:]:
                last = merged[-1]
                if current[0] <= last[1]:
                    merged[-1] = (last[0], max(last[1], current[1]))
                else:
                    merged.append(current)
            length = sum(e[1] - e[0] + 1 for e in merged)
            longest = max(longest, length)
        if gene_id in lookup:
            lookup[gene_id]["gene_length_kb"] = round(longest / 1000.0, 3)
        else:
            lookup[gene_id] = {"gene_length_kb": round(longest / 1000.0, 3)}

    return lookup


def parse_regions_file(regions_file):
    chrom_to_species = {}
    with open(regions_file) as f:
        for line in f:
            parts = line.strip().split("\t")
            species = parts[0]
            chromosomes = parts[1]
            for chrom in chromosomes.split():
                chrom_to_species[chrom] = species
    return chrom_to_species


def read_counts_file(count_file, column, sample_name):
    df = pd.read_csv(
        count_file,
        sep="\t",
        header=None,
        usecols=[0, column - 1],
        names=["gene", sample_name],
    )
    return df.set_index("gene")


def main(
    count_files,
    strandedness_files,
    output_counts,
    output_strand,
    gtf_file,
    regions_file,
    infer_flag,
    manifest_file,
    strandinfo_column,
    infer_fraction,
):
    chrom_to_species = parse_regions_file(regions_file)
    lookup_dict = parse_gtf_lookup(gtf_file)

    # Load manifest if provided
    manifest = None
    if manifest_file:
        try:
            manifest = pd.read_csv(manifest_file, sep=None, engine="python")
        except Exception as e:
            sys.exit(f"❌ ERROR: Failed to read manifest {manifest_file}: {e}")

        if strandinfo_column not in manifest.columns:
            print(
                f"⚠️ WARNING: Column '{strandinfo_column}' not found in manifest. Forcing inference."
            )
            infer_flag = True

    all_counts = []
    strand_info = []

    for count_file, strand_file in zip(count_files, strandedness_files):
        sample_name = os.path.basename(count_file).split(".")[0]

        if not os.path.exists(count_file) or not os.path.exists(strand_file):
            print(f"Skipping {sample_name}, missing files")
            continue

        inferred, frac = infer_strandedness(strand_file, infer_fraction)
        used = inferred  # default

        if not infer_flag:  # manifest-driven
            if manifest is not None and strandinfo_column in manifest.columns:
                row = manifest.loc[manifest.iloc[:, 0] == sample_name]
                if not row.empty:
                    value = str(row.iloc[0][strandinfo_column]).lower()
                    if value in ["forward", "reverse", "unstranded"]:
                        used = value
                    else:
                        print(
                            f"⚠️ WARNING: Invalid strandedness '{value}' in manifest for {sample_name}. Using inferred instead."
                        )
                else:
                    print(
                        f"⚠️ WARNING: Sample {sample_name} not found in manifest. Using inferred instead."
                    )

        strand_info.append((sample_name, inferred, used, round(frac, 3)))

        if used == "unstranded":
            col = 2
        elif used == "forward":
            col = 3
        elif used == "reverse":
            col = 4
        else:
            col = 2  # fallback

        df = read_counts_file(count_file, col, sample_name)
        all_counts.append(df)

    counts_df = pd.concat(all_counts, axis=1).fillna(0).astype(int)
    counts_df = counts_df[~counts_df.index.str.startswith("N_")]

    # Annotate
    annot_rows = []
    for gene_id in counts_df.index:
        info = lookup_dict.get(gene_id, {})
        gene_chr = info.get("gene_chr", "NA")
        species = chrom_to_species.get(gene_chr, "NA")
        annot_rows.append(
            [
                species,
                gene_chr,
                info.get("gene_start", "NA"),
                info.get("gene_end", "NA"),
                info.get("gene_strand", "NA"),
                info.get("gene_length_kb", "NA"),
                info.get("gene_type", "NA"),
            ]
        )

    annot_df = pd.DataFrame(
        annot_rows,
        columns=[
            "species",
            "gene_chr",
            "gene_start",
            "gene_end",
            "gene_strand",
            "gene_length_kb",
            "gene_type",
        ],
        index=counts_df.index,
    )

    final_df = pd.concat([annot_df, counts_df], axis=1)
    final_df.index = final_df.index.map(
        lambda gid: lookup_dict.get(gid, {}).get("gene_id", gid)
        + "|"
        + lookup_dict.get(gid, {}).get("gene_name", "NA")
    )
    final_df.to_csv(output_counts, sep="\t")

    # strand file with 4 columns
    strand_df = pd.DataFrame(
        strand_info,
        columns=["sample", "inferred_strand", "used_strand", "inference_fraction"],
    )
    strand_df.to_csv(output_strand, sep="\t", index=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Build count matrix with gene annotations and strandedness."
    )
    parser.add_argument(
        "--counts", required=True, help="Comma-separated list of count files"
    )
    parser.add_argument(
        "--strandinfo",
        required=True,
        help="Comma-separated list of strandedness summary files",
    )
    parser.add_argument(
        "--output_counts", required=True, help="Path to output annotated count matrix"
    )
    parser.add_argument(
        "--output_strand",
        required=True,
        help="Path to output sample-strandedness table",
    )
    parser.add_argument("--gtf", required=True, help="Gene annotation GTF file")
    parser.add_argument(
        "--regions",
        required=True,
        help="Tab-separated regions file mapping chromosomes to species",
    )

    # new args
    parser.add_argument(
        "--infer_strandedness",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Whether to infer strandedness (default: True). Use --no-infer_strandedness to disable.",
    )
    parser.add_argument("--manifest_file", required=False, help="Path to manifest file")
    parser.add_argument(
        "--strandinfo_column",
        required=False,
        help="Column name in manifest for strandedness info",
    )
    parser.add_argument(
        "--infer_strandedness_fraction",
        type=float,
        default=0.8,
        help="Fraction threshold for inference (default=0.8)",
    )

    args = parser.parse_args()

    count_files = args.counts.split(",")
    strandedness_files = args.strandinfo.split(",")
    output_counts = args.output_counts
    output_strand = args.output_strand

    main(
        count_files,
        strandedness_files,
        output_counts,
        output_strand,
        args.gtf,
        args.regions,
        args.infer_strandedness,
        args.manifest_file,
        args.strandinfo_column,
        args.infer_strandedness_fraction,
    )
    print(f"Output written to {output_counts} and {output_strand}")
    sys.exit(0)
# End of script
