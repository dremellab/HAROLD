import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "workflow" / "scripts" / "_get_strand.py"


def _rule(tmp_path, used_strand, peorse):
    table = tmp_path / "sample_strandedness.tsv"
    table.write_text(
        "sample\tinferred_strand\tused_strand\tinference_fraction\n"
        f"sampleA\t{used_strand}\t{used_strand}\t0.9\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--input",
            str(table),
            "--sample",
            "sampleA",
            "--peorse",
            peorse,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


# RSeQC notation: read number, strand the read maps to, strand of the gene.
# "reverse" in sample_strandedness.tsv means the "1+-,1-+,2++,2--" / "+-,-+"
# fraction of infer_experiment dominates, so that is the rule FPKM_count.py needs.
@pytest.mark.parametrize(
    "used_strand, peorse, expected",
    [
        ("reverse", "PE", "1+-,1-+,2++,2--"),
        ("reverse", "SE", "+-,-+"),
        ("forward", "PE", "1++,1--,2+-,2-+"),
        ("forward", "SE", "++,--"),
        ("unstranded", "PE", "none"),
        ("unstranded", "SE", "none"),
    ],
)
def test_strand_rule_matches_strandedness_label(
    tmp_path, used_strand, peorse, expected
):
    assert _rule(tmp_path, used_strand, peorse) == expected
