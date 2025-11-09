#!/usr/bin/env python3
import argparse
import pandas as pd
import sys

def main():
    parser = argparse.ArgumentParser(
        description="Add TPM column to RSeQC FPKM_count.py output file."
    )
    parser.add_argument("input_file", help="Input .fpkm.xls file from RSeQC")
    parser.add_argument("output_file", help="Output TSV file with TPM column")
    args = parser.parse_args()

    try:
        # Do NOT skip lines starting with '#'
        df = pd.read_csv(args.input_file, sep="\t", engine="python")
    except Exception as e:
        sys.exit(f"❌ Failed to read {args.input_file}: {e}")

    # Fix potential column names like "#chrom"
    df.columns = [c.lstrip("#") for c in df.columns]

    if "FPKM" not in df.columns:
        sys.exit(f"❌ Input file must contain a 'FPKM' column. Columns found: {list(df.columns)}")

    # Convert FPKM to numeric
    df["FPKM"] = pd.to_numeric(df["FPKM"], errors="coerce").fillna(0)

    # Compute TPM
    total_fpkm = df["FPKM"].sum()
    if total_fpkm == 0:
        sys.exit("❌ Total FPKM sum is zero. Cannot compute TPM.")
    df["TPM"] = df["FPKM"] / total_fpkm * 1e6

    # Write to file
    try:
        df.to_csv(args.output_file, sep="\t", index=False, float_format="%.6f")
        print(f"✅ Wrote TPM-appended file: {args.output_file}")
    except Exception as e:
        sys.exit(f"❌ Failed to write {args.output_file}: {e}")

if __name__ == "__main__":
    main()
