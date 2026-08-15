import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "workflow" / "scripts" / "_aggregate_counts_by_strandedness.py"
SPEC = importlib.util.spec_from_file_location("aggregate_counts_by_strandedness", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_counts_matrix_exports_gene_column_without_pandas_index(tmp_path):
    gtf = tmp_path / "genes.gtf"
    gtf.write_text(
        "chr1\tref\tgene\t1\t100\t.\t+\t.\tgene_id \"gene1\"; gene_name \"GENE1\"; gene_type \"protein_coding\"\n"
        "chr1\tref\texon\t1\t100\t.\t+\t.\tgene_id \"gene1\"; transcript_id \"tx1\"; gene_name \"GENE1\"; gene_type \"protein_coding\"\n",
        encoding="utf-8",
    )

    count_file = tmp_path / "sampleA.ReadsPerGene.out.tab"
    count_file.write_text(
        "gene1\t7\t0\t0\n"
        "N_unmapped\t5\t0\t0\n",
        encoding="utf-8",
    )

    strand_file = tmp_path / "sampleA.strandedness.txt"
    strand_file.write_text("not a valid summary\n", encoding="utf-8")

    output_counts = tmp_path / "counts_matrix.tsv"
    output_strand = tmp_path / "sample_strandedness.tsv"
    regions = tmp_path / "regions.tsv"
    regions.write_text("hg38\tchr1\n", encoding="utf-8")

    MODULE.main(
        [str(count_file)],
        [str(strand_file)],
        str(output_counts),
        str(output_strand),
        str(gtf),
        str(regions),
        True,
        None,
        None,
        0.8,
    )

    lines = output_counts.read_text(encoding="utf-8").splitlines()
    assert lines[0].startswith("gene\t")
    assert "Unnamed: 0" not in lines[0]
    assert "gene1|GENE1" in lines[1]
