import pandas as pd
import argparse

def counts_to_rpkm_tpm(df, length_col, sample_cols):
    # Copy full dataframe to preserve non-sample columns
    df_rpkm = df.copy()
    df_tpm = df.copy()

    # Only process sample columns listed in sample_cols
    for col in sample_cols:
        rpk = df[col] / df[length_col]
        total_mapped_millions = df[col].sum() / 1e6
        df_rpkm[col] = rpk / total_mapped_millions
        df_tpm[col] = (rpk / rpk.sum()) * 1e6

    # Non-sample columns (metadata) remain unchanged because of df.copy()
    return df_rpkm, df_tpm

def main():
    parser = argparse.ArgumentParser(description='Convert raw counts to RPKM and TPM values using sample list, preserving metadata columns.')
    parser.add_argument('-i', '--input', required=True, help='Input TSV/CSV file with counts and gene lengths (in kb).')
    parser.add_argument('-s', '--samples', required=True, help='TSV file with a column named sampleName listing sample columns to process.')
    parser.add_argument('-o1', '--rpkm_output', required=True, help='Output TSV file for RPKM values.')
    parser.add_argument('-o2', '--tpm_output', required=True, help='Output TSV file for TPM values.')
    parser.add_argument('--sep', default='\t', help='Column separator (default: tab).')
    parser.add_argument('--length_col', default='gene_length_kb', help='Column name for gene length in kb.')

    args = parser.parse_args()

    # Load data and sample list
    df = pd.read_csv(args.input, sep=args.sep)
    sample_df = pd.read_csv(args.samples, sep=args.sep)

    sample_cols = sample_df['sampleName'].tolist()
    missing = [c for c in sample_cols if c not in df.columns]
    if missing:
        raise ValueError(f"Samples not found in input file: {missing}")

    df_rpkm, df_tpm = counts_to_rpkm_tpm(df, args.length_col, sample_cols)

    df_rpkm.to_csv(args.rpkm_output, sep='\t', index=False)
    df_tpm.to_csv(args.tpm_output, sep='\t', index=False)

if __name__ == '__main__':
    main()
