import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "workflow" / "scripts"
FIX_GTF = SCRIPTS / "_fix_gtf.py"
ADD_GENEID = SCRIPTS / "_add_geneid_to_genepred.py"


def _gtf_line(feature, attrs):
    return "\t".join(["chr1", "src", feature, "1", "100", ".", "+", ".", attrs]) + "\n"


def _run(script, args, cwd):
    return subprocess.run(
        [sys.executable, str(script), *args], cwd=cwd, capture_output=True, text=True
    )


def test_fix_gtf_keeps_values_with_spaces(tmp_path):
    gtf = tmp_path / "in.gtf"
    gtf.write_text(
        _gtf_line(
            "transcript",
            'gene_id "g1"; transcript_id "t1"; transcript_name "UL3 *1"; '
            'note "a; b"; exon_number 1;',
        )
    )
    res = _run(FIX_GTF, ["--ingtf", str(gtf), "--outgtf", str(tmp_path / "out.gtf")], tmp_path)
    assert res.returncode == 0, res.stderr
    attrs = (tmp_path / "out.gtf").read_text().split("\t")[8]
    assert 'transcript_id "t1"' in attrs
    assert 'transcript_name "UL3 *1"' in attrs
    assert 'note "a; b"' in attrs
    assert 'exon_number "1"' in attrs
    assert 'gene_name "g1"' in attrs  # filled in from gene_id


def test_fix_gtf_fails_loudly_on_id_with_spaces(tmp_path):
    gtf = tmp_path / "in.gtf"
    gtf.write_text(_gtf_line("transcript", 'gene_id "g1"; transcript_id "UL17.4 sORF 2";'))
    res = _run(FIX_GTF, ["--ingtf", str(gtf), "--outgtf", str(tmp_path / "out.gtf")], tmp_path)
    assert res.returncode != 0
    assert 'transcript_id "UL17.4 sORF 2" contains whitespace' in res.stderr


def test_add_geneid_prepends_gene_id(tmp_path):
    gtf = tmp_path / "in.gtf"
    gtf.write_text(_gtf_line("transcript", 'gene_id "g1"; transcript_id "t1"; note "x y";'))
    gp = tmp_path / "in.gp"
    gp.write_text("t1\tchr1\t+\t0\t100\n")
    res = _run(ADD_GENEID, [str(gtf), str(gp)], tmp_path)
    assert res.returncode == 0, res.stderr
    assert res.stdout == "g1\tt1\tchr1\t+\t0\t100\n"


def test_add_geneid_errors_go_to_stderr(tmp_path):
    gtf = tmp_path / "in.gtf"
    gtf.write_text(_gtf_line("transcript", 'gene_id "g1";'))
    gp = tmp_path / "in.gp"
    gp.write_text("t1\tchr1\n")
    res = _run(ADD_GENEID, [str(gtf), str(gp)], tmp_path)
    assert res.returncode == 1
    assert res.stdout == ""
    assert "does not have transcript_id" in res.stderr


def test_add_geneid_unknown_transcript_goes_to_stderr(tmp_path):
    gtf = tmp_path / "in.gtf"
    gtf.write_text(_gtf_line("transcript", 'gene_id "g1"; transcript_id "t1";'))
    gp = tmp_path / "in.gp"
    gp.write_text("t2\tchr1\n")
    res = _run(ADD_GENEID, [str(gtf), str(gp)], tmp_path)
    assert res.returncode == 1
    assert "'t2'" in res.stderr and res.stdout == ""


def test_aggregate_counts_gtf_parser_handles_semicolons_in_values(tmp_path):
    # ref.fixed.gtf keeps quoted values such as cds_check "aa_subs;start_codon_changed(ATG>ACG)";
    # the strandedness aggregator must parse them instead of failing on the split-off piece
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "agg", SCRIPTS / "_aggregate_counts_by_strandedness.py"
    )
    agg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(agg)
    gtf = tmp_path / "ref.fixed.gtf"
    gtf.write_text(
        _gtf_line("gene", 'gene_id "g1"; gene_name "G1 x"; gene_type "protein_coding";')
        + _gtf_line(
            "transcript",
            'gene_id "g1"; transcript_id "t1"; gene_name "G1 x"; '
            'cds_check "aa_subs;start_codon_changed(ATG>ACG)";',
        )
        + _gtf_line("exon", 'gene_id "g1"; transcript_id "t1"; gene_name "G1 x";')
    )
    lookup = agg.parse_gtf_lookup(str(gtf))
    assert lookup["g1"]["gene_name"] == "G1 x"
    assert lookup["g1"]["gene_type"] == "protein_coding"
