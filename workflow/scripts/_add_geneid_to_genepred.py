import sys

"""
This script is designed to map transcript IDs to their corresponding gene IDs using a
GTF (Gene Transfer Format) file. It reads a GTF file to build a mapping of
transcript_id → gene_id, then takes a second input file (e.g., a table with transcript IDs)
and prepends the corresponding gene ID to each row.
"""


def get_id(s, whatid):
    parts = s.split()
    if whatid not in parts:
        print(f"{s} does not have {whatid}")
        sys.exit(1)
        return None  # or return "" or raise Exception

    for i, j in enumerate(parts):
        if j == whatid:
            r = parts[i + 1]
            r = r.replace('"', "").replace(";", "")
            return r


gtffile = sys.argv[1]
transcript2gene = dict()
for i in open(gtffile).readlines():
    if i.startswith("#"):
        continue
    i = i.strip().split("\t")
    if i[2] != "transcript":
        continue
    gid = get_id(i[8], "gene_id")
    tid = get_id(i[8], "transcript_id")
    # 	print("%s\t%s"%(tid,gid))
    transcript2gene[tid] = gid

for i in open(sys.argv[2]).readlines():
    j = i.strip().split("\t")
    x = []
    tid = j.pop(0)
    gid = transcript2gene[tid]
    x.append(gid)
    x.append(tid)
    x.extend(j)
    print("\t".join(x))
