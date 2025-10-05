#!/usr/bin/env python3

import pandas as pd
from pathlib import Path
import sys


def get_sample_name(path: Path) -> str:
    """Extract sample name from filename like KOS_8h_R1.Aligned.sortedByCoord.out.tin.xls"""
    return path.stem.replace(".Aligned.sortedByCoord.out.tin", "")


def main(file_list, output="aggregate_tin.tsv"):
    dfs = []

    for file in file_list:
        path = Path(file)
        sample = get_sample_name(path)

        # Read as tab-delimited
        df = pd.read_csv(path, sep="\t")

        # Keep first 4 columns, rename TIN to sample name
        df = df[["geneID", "chrom", "tx_start", "tx_end", "TIN"]].copy()
        df = df.rename(columns={"TIN": sample})

        dfs.append(df)

    # Merge all on the first four columns
    merged = dfs[0]
    for df in dfs[1:]:
        merged = pd.merge(
            merged, df, on=["geneID", "chrom", "tx_start", "tx_end"], how="outer"
        )

    # Save to file
    merged.to_csv(output, sep="\t", index=False)
    # print(f"✅ Wrote {output} with {len(merged)} rows and {len(merged.columns)-4} samples")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} file1.tin.xls file2.tin.xls ...")
        sys.exit(1)
    main(sys.argv[1:])
