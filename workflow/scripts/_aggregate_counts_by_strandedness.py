import os
import pandas as pd
import re
from glob import glob


def infer_strandedness(file_path):
    with open(file_path) as f:
        content = f.read()
    if "Fraction of reads explained by" not in content:
        return "unstranded"  # fallback
    match = re.findall(r'Fraction of reads explained by "(.*?)": (\d+\.\d+)', content)
    if not match or len(match) < 2:
        return "unstranded"

    first_type, first_frac = match[0]
    second_type, second_frac = match[1]
    first_frac = float(first_frac)
    second_frac = float(second_frac)

    if first_frac > 0.8:
        return "reverse"
    elif second_frac > 0.8:
        return "forward"
    else:
        return "unstranded"


def read_counts_file(count_file, column, sample_name):
    df = pd.read_csv(
        count_file,
        sep="\t",
        header=None,
        usecols=[0, column - 1],
        names=["gene", sample_name],
    )
    return df.set_index("gene")


def main(input_dirs, output_counts, output_strand):
    all_counts = []
    strand_info = []

    for sample_dir in input_dirs:
        sample_name = os.path.basename(os.path.dirname(sample_dir.rstrip("/")))
        infer_file = os.path.join(sample_dir, sample_name + ".strandedness.txt")
        read_counts_file_path = os.path.join(
            sample_dir, sample_name + ".ReadsPerGene.out.tab"
        )

        if not os.path.exists(infer_file) or not os.path.exists(read_counts_file_path):
            print(f"Skipping {sample_name}, missing files")
            continue

        strandedness = infer_strandedness(infer_file)
        strand_info.append((sample_name, strandedness))

        if strandedness == "unstranded":
            col = 2
        elif strandedness == "forward":
            col = 3
        elif strandedness == "reverse":
            col = 4
        else:
            col = 2  # fallback

        df = read_counts_file(read_counts_file_path, col, sample_name)
        all_counts.append(df)

    counts_df = pd.concat(all_counts, axis=1).fillna(0).astype(int)
    # 🔍 Remove rows (genes) where gene name starts with "N_"
    counts_df = counts_df[~counts_df.index.str.startswith("N_")]
    counts_df.to_csv(output_counts, sep="\t")

    strand_df = pd.DataFrame(strand_info, columns=["sample", "strandedness"])
    strand_df.to_csv(output_strand, sep="\t", index=False)


if __name__ == "__main__":
    import sys

    sample_dirs_file = sys.argv[1]
    output_counts = sys.argv[2]
    output_strand = sys.argv[3]

    with open(sample_dirs_file) as f:
        input_dirs = [line.strip() for line in f if line.strip()]

    main(input_dirs, output_counts, output_strand)
