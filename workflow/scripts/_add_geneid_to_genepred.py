import re
import sys

"""
This script is designed to map transcript IDs to their corresponding gene IDs using a
GTF (Gene Transfer Format) file. It reads a GTF file to build a mapping of
transcript_id → gene_id, then takes a second input file (e.g., a table with transcript IDs)
and prepends the corresponding gene ID to each row.

Output goes to stdout (redirected to the output file by the rule), so every error message
goes to stderr -- otherwise it ends up in the output file, which Snakemake deletes on
failure, and the rule log only shows a bare non-zero exit status.
"""

# key "quoted value"; or key unquoted_value; -- quoted values may contain spaces and ';'
ATTR_RE = re.compile(r'([^\s";]+)\s+(?:"([^"]*)"|([^\s";]+))')


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def get_id(s, whatid):
    for m in ATTR_RE.finditer(s):
        if m.group(1) == whatid:
            return m.group(2) if m.group(2) is not None else m.group(3)
    die(f"GTF transcript line does not have {whatid}: {s}")


def main(argv):
    if len(argv) != 2:
        die("usage: _add_geneid_to_genepred.py <gtf> <genepred>")
    gtffile, genepredfile = argv

    transcript2gene = dict()
    with open(gtffile) as f:
        for i in f:
            if i.startswith("#"):
                continue
            i = i.strip().split("\t")
            if len(i) < 9 or i[2] != "transcript":
                continue
            gid = get_id(i[8], "gene_id")
            tid = get_id(i[8], "transcript_id")
            transcript2gene[tid] = gid

    with open(genepredfile) as f:
        for i in f:
            j = i.strip().split("\t")
            tid = j.pop(0)
            if tid not in transcript2gene:
                die(
                    f"transcript {tid!r} in {genepredfile} has no transcript line in {gtffile}"
                )
            print("\t".join([transcript2gene[tid], tid] + j))


if __name__ == "__main__":
    main(sys.argv[1:])
