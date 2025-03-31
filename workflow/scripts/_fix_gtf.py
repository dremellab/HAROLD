import argparse

"""
This script processes a GTF (Gene Transfer Format) file to ensure that every entry has a `gene_name` attribute.
If the `gene_name` attribute is missing, it attempts to infer it from the `gene_id` attribute using a mapping
constructed from the input GTF file. The script performs the following steps:

1. **Parse Command-Line Arguments**:
   - `--ingtf`: Specifies the input GTF file.
   - `--outgtf`: Specifies the output GTF file.

2. **Define Helper Functions**:
   - `get_attributes(attstr)`: Parses the attributes column of a GTF file (column 9) into a dictionary.
   - `get_attstr(att)`: Converts a dictionary of attributes back into a properly formatted GTF attributes string.

3. **Build a Mapping of `gene_id` to `gene_name`**:
   - Reads the input GTF file line by line.
   - Skips comment lines (lines starting with `#`).
   - Ensures each line has exactly 9 tab-separated fields.
   - Extracts the `gene_id` and `gene_name` attributes from the attributes column.
   - Constructs a dictionary (`gene_id_2_gene_name`) mapping `gene_id` to `gene_name`. If `gene_name` is missing,
     the `gene_id` is used as a fallback.

4. **Write the Mapping to a Temporary File**:
   - Outputs the `gene_id` to `gene_name` mapping to a file named `gene_id_2_gene_name.tsv`.

5. **Process the Input GTF File**:
   - Reads the input GTF file again and writes the processed lines to the output GTF file.
   - For each line:
     - Skips comment lines.
     - Parses the attributes column.
     - Ensures that the `gene_name` attribute exists:
       - If missing, looks up the `gene_name` using the `gene_id` in the `gene_id_2_gene_name` dictionary.
       - If the `gene_id` is not found in the dictionary, the script exits with an error.
     - Updates the attributes column with the `gene_name` and writes the modified line to the output file.

6. **Error Handling**:
   - Ensures that each line in the GTF file has exactly 9 fields.
   - Exits with an error if a `gene_id` is missing or cannot be resolved to a `gene_name`.

The script is designed to standardize GTF files by ensuring that all entries have a `gene_name` attribute, which is
often required for downstream bioinformatics analyses.
"""
debug = 0


def get_attributes(attstr):
    att = dict()
    attlist = attstr.strip().split(";")
    if debug == 1:
        print(attstr)
    if debug == 1:
        print(attlist)
    for item in attlist:
        x = item.strip()
        if debug == 1:
            print(x)
        x = x.replace('"', "")
        if debug == 1:
            print(x)
        x = x.split()
        if debug == 1:
            print(x)
        if len(x) != 2:
            continue
        key = x.pop(0)
        key = key.replace(":", "")
        value = " ".join(x)
        value = value.replace(":", "_")
        att[key] = value
    return att


def get_attstr(att):
    strlist = []
    for k, v in att.items():
        s = '%s "%s"' % (k, v)
        strlist.append(s)
    attstr = "; ".join(strlist)
    return attstr + ";"


parser = argparse.ArgumentParser(description="fix gtf file")
parser.add_argument(
    "--ingtf", dest="ingtf", type=str, required=True, help="input gtf file"
)
parser.add_argument(
    "--outgtf", dest="outgtf", type=str, required=True, help="output gtf file"
)
args = parser.parse_args()

gene_id_2_gene_name = dict()

with open(args.ingtf, "r") as ingtf:
    for line in ingtf:
        if line.startswith("#"):
            continue
        line = line.strip()
        line = line.split("\t")
        if len(line) != 9:
            print(line)
            exit("ERROR ... line does not have 9 items!")
        attributes = get_attributes(line[8])
        if debug == 1:
            print(line)
        if debug == 1:
            print(attributes)
        if not attributes["gene_id"] in gene_id_2_gene_name:
            if "gene_name" in attributes:
                gene_id_2_gene_name[attributes["gene_id"]] = attributes["gene_name"]
            else:
                gene_id_2_gene_name["gene_id"] = attributes["gene_id"]

with open("gene_id_2_gene_name.tsv", "w") as tmp:
    for k, v in gene_id_2_gene_name.items():
        tmp.write("%s\t%s\n" % (k, v))

with open(args.ingtf, "r") as ingtf, open(args.outgtf, "w") as outgtf:
    for line in ingtf:
        if line.startswith("#"):
            outgtf.write(line)
            continue
        line = line.strip()
        line = line.split("\t")
        attributes = get_attributes(line[8])
        if not "gene_name" in attributes:
            if not "gene_id" in attributes:
                print(line)
                print(attributes)
                exit("ERROR in this line!")
            if not attributes["gene_id"] in gene_id_2_gene_name:
                print(line)
                print(attributes)
                print(attributes["gene_id"])
                exit("ERROR2 in this line!")
            attributes["gene_name"] = gene_id_2_gene_name[attributes["gene_id"]]
        line[8] = get_attstr(attributes)
        outgtf.write("\t".join(line) + "\n")
