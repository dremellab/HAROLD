import os
import sys
import pandas as pd
import re
from collections import defaultdict
import argparse
from pprint import pprint


def infer_strandedness(file_path):
    with open(file_path) as f:
        content = f.read()
    if "Fraction of reads explained by" not in content:
        return "unstranded"
    match = re.findall(r"Fraction of reads explained by \"(.*?)\": (\d+\.\d+)", content)
    if not match or len(match) < 2:
        return "unstranded"

    first_type, first_frac = match[0]
    second_type, second_frac = match[1]
    first_frac = float(first_frac)
    second_frac = float(second_frac)

    if first_frac > 0.8:
        return "forward"
    elif second_frac > 0.8:
        return "reverse"
    else:
        return "unstranded"


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
):
    chrom_to_species = parse_regions_file(regions_file)
    lookup_dict = parse_gtf_lookup(gtf_file)

    all_counts = []
    strand_info = []

    for count_file, strand_file in zip(count_files, strandedness_files):
        sample_name = os.path.basename(count_file).split(".")[0]

        if not os.path.exists(count_file) or not os.path.exists(strand_file):
            print(f"Skipping {sample_name}, missing files")
            continue

        strandedness = infer_strandedness(strand_file)
        strand_info.append((sample_name, strandedness))

        if strandedness == "unstranded":
            col = 2
        elif strandedness == "forward":
            col = 3
        elif strandedness == "reverse":
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

    strand_df = pd.DataFrame(strand_info, columns=["sample", "strandedness"])
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
    args = parser.parse_args()

    count_files = args.counts.split(",")
    strandedness_files = args.strandinfo.split(",")
    output_counts = args.output_counts
    output_strand = args.output_strand
    gtf_file = args.gtf
    regions_file = args.regions

    main(
        count_files,
        strandedness_files,
        output_counts,
        output_strand,
        gtf_file,
        regions_file,
    )
    print(f"Output written to {output_counts} and {output_strand}")
    sys.exit(0)
# End of script
