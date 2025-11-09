#!/usr/bin/env python3
import argparse
import pandas as pd
import sys

def main():
    parser = argparse.ArgumentParser(
        description="Extract RSeQC-compatible strand rule for a given sample required by get_FPKM.py"
    )
    parser.add_argument("--input", required=True, help="Path to sample_strandedness.tsv")
    parser.add_argument("--sample", required=True, help="Sample name to extract strand info for")
    parser.add_argument("--peorse", required=True, choices=["PE", "SE"],
                        help="Specify sequencing type: PE (paired-end) or SE (single-end)")
    args = parser.parse_args()

    # Load table
    try:
        df = pd.read_csv(args.input, sep="\t", dtype=str)
    except Exception as e:
        sys.exit(f"❌ Failed to read {args.input}: {e}")

    # Validate columns
    if "sample" not in df.columns or "used_strand" not in df.columns:
        sys.exit("❌ Input file must contain 'sample' and 'used_strand' columns.")

    # Find sample
    row = df.loc[df["sample"] == args.sample]
    if row.empty:
        sys.exit(f"❌ Sample '{args.sample}' not found in {args.input}.")

    used_strand = row["used_strand"].iloc[0].strip().lower()

    # Determine strand rule
    if used_strand == "unstranded":
        rule = "none"
    elif used_strand == "reverse":
        rule = "1++,1--,2+-,2-+" if args.peorse == "PE" else "++,--"
    elif used_strand == "forward":
        rule = "1+-,1-+,2++,2--" if args.peorse == "PE" else "+-,-+"
    else:
        sys.exit(f"❌ Unknown used_strand '{used_strand}' for sample '{args.sample}'.")

    print(rule)

if __name__ == "__main__":
    main()
