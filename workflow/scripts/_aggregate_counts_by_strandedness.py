import os
import sys
import pandas as pd
import re


def infer_strandedness(file_path):
    with open(file_path) as f:
        content = f.read()
    if "Fraction of reads explained by" not in content:
        return "unstranded"
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


def main(count_files, strandedness_files, output_counts, output_strand):
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
    counts_df.to_csv(output_counts, sep="\t")

    strand_df = pd.DataFrame(strand_info, columns=["sample", "strandedness"])
    strand_df.to_csv(output_strand, sep="\t", index=False)


if __name__ == "__main__":
    count_files = sys.argv[1].split(",")
    strandedness_files = sys.argv[2].split(",")
    output_counts = sys.argv[3]
    output_strand = sys.argv[4]

    main(count_files, strandedness_files, output_counts, output_strand)
