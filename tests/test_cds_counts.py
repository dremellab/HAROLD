import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "workflow" / "scripts"))

import _aggregate_cds_counts as agg  # noqa: E402
import _build_cds_gtf as bcg  # noqa: E402


def _row(chrom, feature, start, end, gene_id, frame="."):
    attrs = f'gene_id "{gene_id}"; transcript_id "t1";'
    return (
        "\t".join([chrom, "src", feature, str(start), str(end), ".", "+", frame, attrs])
        + "\n"
    )


def _features(path, chrom):
    rows = [ln.split("\t") for ln in Path(path).read_text().splitlines()]
    return [r[2] for r in rows if r[0] == chrom]


def _build(tmp_path, rows, host="hg38"):
    gtf = tmp_path / "ref.fixed.gtf"
    gtf.write_text("# comment\n" + "".join(rows))
    regions = tmp_path / "ref.fa.regions"
    regions.write_text("hg38\tchr1 chr2 \nERCC\tERCC_1 ERCC_2\nNC_1\tNC_1\nBAC\tBAC\n")
    out = tmp_path / "ref.cds.gtf"
    rc = bcg.main(
        [
            "--ingtf",
            str(gtf),
            "--regions",
            str(regions),
            "--host",
            host,
            "--outgtf",
            str(out),
        ]
    )
    assert rc == 0
    return out


def test_exons_copied_as_cds_only_for_nonhost_genomes_without_cds(tmp_path):
    out = _build(
        tmp_path,
        [
            _row("chr1", "exon", 1, 100, "H1"),
            _row("chr1", "CDS", 10, 90, "H1", frame="0"),
            _row("chr2", "exon", 1, 50, "H2"),  # non-coding host gene
            _row("ERCC_1", "exon", 1, 20, "E1"),
            _row("ERCC_2", "exon", 1, 30, "E2"),
            _row("NC_1", "gene", 1, 50, "V1"),
            _row("NC_1", "exon", 1, 20, "V1"),
            _row("NC_1", "exon", 30, 50, "V1"),
            _row("BAC", "exon", 1, 30, "B1"),
            _row("BAC", "CDS", 4, 27, "B1", frame="0"),
            _row("chrUn", "exon", 1, 30, "U1"),  # not in the regions file
        ],
    )
    assert _features(out, "chr1") == ["exon", "CDS"]
    assert _features(out, "chr2") == ["exon"]
    assert _features(out, "ERCC_1") == ["exon", "CDS"]
    assert _features(out, "ERCC_2") == ["exon", "CDS"]
    assert _features(out, "NC_1") == ["gene", "exon", "CDS", "exon", "CDS"]
    assert _features(out, "BAC") == ["exon", "CDS"]
    assert _features(out, "chrUn") == ["exon"]
    cds = [
        ln.split("\t")
        for ln in out.read_text().splitlines()
        if ln.startswith("NC_1\tsrc\tCDS")
    ]
    assert [(c[3], c[4], c[7]) for c in cds] == [("1", "20", "0"), ("30", "50", "0")]


def test_host_without_cds_is_left_alone(tmp_path):
    out = _build(tmp_path, [_row("chr1", "exon", 1, 100, "H1")])
    assert _features(out, "chr1") == ["exon"]


def _fc(path, bam, counts):
    lines = ['# Program:featureCounts v2.0.6; Command:"featureCounts"']
    lines.append("\t".join(["Geneid", "Chr", "Start", "End", "Strand", "Length", bam]))
    for gene, n in counts.items():
        lines.append("\t".join([gene, "chr1", "1", "100", "+", "100", str(n)]))
    path.write_text("\n".join(lines) + "\n")
    summary = Path(str(path).replace(".tsv", ".summary.tsv"))
    summary.write_text(f"Status\t{bam}\nAssigned\t{sum(counts.values())}\n")
    return str(path), str(summary)


def test_aggregate_matches_ribold_layout(tmp_path):
    c1, s1 = _fc(tmp_path / "a.tsv", "/x/a.bam", {"g1": 5, "g2": 0})
    c2, s2 = _fc(tmp_path / "b.tsv", "/x/b.bam", {"g1": 7, "g2": 3})
    out_c, out_s = tmp_path / "m.tsv", tmp_path / "m.summary.tsv"
    rc = agg.main(
        [
            "--samples",
            "a,b",
            "--counts",
            f"{c1},{c2}",
            "--summaries",
            f"{s1},{s2}",
            "--output_counts",
            str(out_c),
            "--output_summary",
            str(out_s),
        ]
    )
    assert rc == 0
    assert out_c.read_text() == "gene_id\ta\tb\ng1\t5\t7\ng2\t0\t3\n"
    assert out_s.read_text() == "Status\ta\tb\nAssigned\t5\t10\n"


def test_aggregate_fails_on_mismatched_genes(tmp_path):
    c1, s1 = _fc(tmp_path / "a.tsv", "/x/a.bam", {"g1": 5})
    c2, s2 = _fc(tmp_path / "b.tsv", "/x/b.bam", {"g1": 7, "g2": 3})
    rc = agg.main(
        [
            "--samples",
            "a,b",
            "--counts",
            f"{c1},{c2}",
            "--summaries",
            f"{s1},{s2}",
            "--output_counts",
            str(tmp_path / "m.tsv"),
            "--output_summary",
            str(tmp_path / "m.summary.tsv"),
        ]
    )
    assert rc == 1
