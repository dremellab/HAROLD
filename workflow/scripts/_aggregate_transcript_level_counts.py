import pandas as pd
import argparse
import os
import re

def parse_gtf(gtf_path):
    gtf_data = {}
    with open(gtf_path, 'r') as gtf:
        for line in gtf:
            if line.startswith('#'):
                continue
            fields = line.strip().split('\t')
            if len(fields) < 9 or fields[2] != 'transcript':
                continue
            attributes = fields[8]
            gene_id_match = re.search('gene_id "(.*?)"', attributes)
            transcript_id_match = re.search('transcript_id "(.*?)"', attributes)
            gene_name_match = re.search('gene_name "(.*?)"', attributes)

            if transcript_id_match:
                transcript_id = transcript_id_match.group(1)
                gene_id = gene_id_match.group(1) if gene_id_match else 'NA'
                gene_name = gene_name_match.group(1) if gene_name_match else gene_id
                gtf_data[transcript_id] = {'gene_id': gene_id, 'gene_name': gene_name}
    return pd.DataFrame.from_dict(gtf_data, orient='index').reset_index().rename(columns={'index': 'transcript_id'})

def merge_with_gtf(df, gtf_df):
    df = df.rename(columns={'accession': 'transcript_id'})
    merged = pd.merge(df, gtf_df, on='transcript_id', how='left')
    merged['gene_name'] = merged['gene_name'].fillna(merged['gene_id'])
    return merged

def aggregate_files(input_files, gtf_path, output_fpkm, output_tpm, output_fragcount):
    gtf_df = parse_gtf(gtf_path)

    common_cols = ["chrom", "st", "end", "transcript_id", "mRNA_size", "gene_strand"]
    fpkm_list, tpm_list, fragcount_list = [], [], []

    for f in input_files:
        sample_name = os.path.basename(f).replace(".rseqc_fpkm_tpm.tsv", "")
        df = pd.read_csv(f, sep='\t')

        if 'FPKM' not in df.columns or 'TPM' not in df.columns or 'Frag_count' not in df.columns:
            raise ValueError(f"File {f} missing one of the required columns: FPKM, TPM, or Frag_count.")

        df = merge_with_gtf(df, gtf_df)

        fpkm_df = df[common_cols + ['gene_id', 'gene_name', 'FPKM']].copy()
        tpm_df = df[common_cols + ['gene_id', 'gene_name', 'TPM']].copy()
        fragcount_df = df[common_cols + ['gene_id', 'gene_name', 'Frag_count']].copy()

        fpkm_df.rename(columns={'FPKM': sample_name}, inplace=True)
        tpm_df.rename(columns={'TPM': sample_name}, inplace=True)
        fragcount_df.rename(columns={'Frag_count': sample_name}, inplace=True)

        fpkm_list.append(fpkm_df)
        tpm_list.append(tpm_df)
        fragcount_list.append(fragcount_df)

    def merge_list(df_list):
        merged = df_list[0]
        for df_next in df_list[1:]:
            merged = pd.merge(merged, df_next, on=common_cols + ['gene_id', 'gene_name'], how='inner')
        return merged

    fpkm_merged = merge_list(fpkm_list)
    tpm_merged = merge_list(tpm_list)
    fragcount_merged = merge_list(fragcount_list)

    fpkm_merged.to_csv(output_fpkm, sep='\t', index=False)
    tpm_merged.to_csv(output_tpm, sep='\t', index=False)
    fragcount_merged.to_csv(output_fragcount, sep='\t', index=False)

def main():
    parser = argparse.ArgumentParser(description='Aggregate rseqc_fpkm_tpm.tsv files with GTF gene annotations into combined FPKM, TPM, and Frag_count matrices.')
    parser.add_argument('--input', nargs='+', required=True, help='List of input rseqc_fpkm_tpm.tsv files to aggregate.')
    parser.add_argument('--gtf', required=True, help='Reference GTF file (e.g., ref.fixed.gtf).')
    parser.add_argument('-o1', '--fpkm_output', default='counts_matrix.transcript_level.fpkm.tsv', help='Output file for aggregated FPKM matrix.')
    parser.add_argument('-o2', '--tpm_output', default='counts_matrix.transcript_level.tpm.tsv', help='Output file for aggregated TPM matrix.')
    parser.add_argument('-o3', '--fragcount_output', default='counts_matrix.transcript_level.fragcount.tsv', help='Output file for aggregated Frag_count matrix.')

    args = parser.parse_args()

    aggregate_files(args.input, args.gtf, args.fpkm_output, args.tpm_output, args.fragcount_output)

if __name__ == '__main__':
    main()
