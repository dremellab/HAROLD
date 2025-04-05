###################################################################################
# Function definitions
###################################################################################

def _is_true(variable):
    if variable == True or variable == "True" or variable == "TRUE":
        return True
    else:
        return False

###################################################################################

def _convert_to_int(variable):
    if variable:
        return 1  # True
    if not variable:
        return 0  # False
    return -1  # Unknown

###################################################################################

def append_files_in_list(flist, ofile):
    if not os.path.exists(ofile):
        print("FILE %s does not exist! Creating it!"%(ofile),flush=True)
        with open(ofile, "w") as outfile:
            for fname in flist:
                with open(fname) as infile:
                    for line in infile:
                        outfile.write(line)
    return True

###################################################################################

def get_peorse(wildcards):
    peorse = SAMPLESDF.loc[SAMPLESDF['sampleName'] == wildcards.sample, 'PEorSE'].values[0]
    return peorse

###################################################################################

## Load cluster.json
with open(config["cluster"]) as json_file:
    CLUSTER = yaml.safe_load(json_file)

## Create lambda functions to allow a way to insert read-in values
## as rule directives
getthreads = (
    lambda rname: int(CLUSTER[rname]["threads"])
    if rname in CLUSTER and "threads" in CLUSTER[rname]
    else int(CLUSTER["__default__"]["threads"])
)
getmemg = (
    lambda rname: CLUSTER[rname]["mem"]
    if rname in CLUSTER and "mem" in CLUSTER[rname]
    else CLUSTER["__default__"]["mem"]
)
getmemG = lambda rname: getmemg(rname).replace("g", "G")

###################################################################################
###################################################################################


# resource absolute path
WORKDIR = config["workdir"]
TEMPDIR = config["tempdir"]
SCRIPTS_DIR = config["scriptsdir"]
RESOURCES_DIR = config["resourcesdir"]
FASTAS_GTFS_DIR = config["fastas_gtfs_dir"]

REF_DIR = join(WORKDIR, "ref")
if not os.path.exists(REF_DIR):
    os.mkdir(REF_DIR)
STAR_INDEX_DIR = join(REF_DIR, "STAR_no_GTF")
if not os.path.exists(STAR_INDEX_DIR):
    os.mkdir(STAR_INDEX_DIR)
# strip trailing slashes if any
for d in [
    WORKDIR,
    SCRIPTS_DIR,
    RESOURCES_DIR,
    FASTAS_GTFS_DIR,
    STAR_INDEX_DIR,
    REF_DIR,
]:
    d = d.strip("r\/")

HOST = config["host"]  # hg38 or mm39
ADDITIVES = config["additives"]  # ERCC and/or BAC16Insert
ADDITIVES = ADDITIVES.replace(" ", "")
if ADDITIVES != "":
    HOST_ADDITIVES = HOST + "," + ADDITIVES
else:
    HOST_ADDITIVES = HOST
VIRUSES = config["viruses"]
VIRUSES = VIRUSES.replace(" ", "")
if VIRUSES != "":
    HOST_ADDITIVES_VIRUSES = HOST_ADDITIVES + "," + VIRUSES
    HOST_VIRUSES = HOST + "," + VIRUSES
else:
    HOST_VIRUSES = HOST
    HOST_ADDITIVES_VIRUSES = HOST_ADDITIVES

REPEATS_GTF = join(FASTAS_GTFS_DIR, HOST + ".repeats.gtf")

HOST_ADDITIVES_VIRUSES = HOST_ADDITIVES_VIRUSES.split(",")
FASTAS = [join(FASTAS_GTFS_DIR, f + ".fa") for f in HOST_ADDITIVES_VIRUSES]
REGIONS = [join(FASTAS_GTFS_DIR, f + ".fa.regions") for f in HOST_ADDITIVES_VIRUSES]
if HOST != "":
    REGIONS_HOST = [join(FASTAS_GTFS_DIR, f + ".fa.regions") for f in HOST.split(",")]
else:
    REGIONS_HOST = []
if VIRUSES != "":
    REGIONS_VIRUSES = [join(FASTAS_GTFS_DIR, f + ".fa.regions") for f in VIRUSES.split(",")]
else:
    REGIONS_VIRUSES = []
GTFS = [join(FASTAS_GTFS_DIR, f + ".gtf") for f in HOST_ADDITIVES_VIRUSES]
FASTAS_REGIONS_GTFS = FASTAS.copy()
FASTAS_REGIONS_GTFS.extend(REGIONS)
FASTAS_REGIONS_GTFS.extend(GTFS)

print("FASTAS_REGIONS_GTFS: ", FASTAS_REGIONS_GTFS)

REF_FA = join(REF_DIR, "ref.fa")
REF_REGIONS = join(REF_DIR, "ref.fa.regions")
REF_REGIONS_HOST = join(REF_DIR, "ref.fa.regions.host")
REF_REGIONS_VIRUSES = join(REF_DIR, "ref.fa.regions.viruses")
REF_GTF = join(REF_DIR, "ref.gtf")
append_files_in_list(FASTAS, REF_FA)
append_files_in_list(REGIONS, REF_REGIONS)

###################################################################################################
# check if sequence IDs are unique for unique genome names

print("Validating ref.regions file for unique genome names and sequence IDs...")
input_file = REF_REGIONS

seqid_to_genomes = defaultdict(set)
seen_genomes = set()
duplicate_genomes = set()

with open(input_file) as f:
    for line_number, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        genome = parts[0]
        seq_ids = parts[1:]

        # Check for repeated genome names
        if genome in seen_genomes:
            duplicate_genomes.add(genome)
        seen_genomes.add(genome)

        # Track which genomes each sequence ID appears under
        for seq in seq_ids:
            seqid_to_genomes[seq].add(genome)

# Detect conflicts in sequence IDs
conflicts = {seq: genomes for seq, genomes in seqid_to_genomes.items() if len(genomes) > 1}

# Report issues
if duplicate_genomes:
    print("\n❌ The following genome names are repeated:")
    for g in sorted(duplicate_genomes):
        print(f"  {g}")

if conflicts:
    print("\n❌ The following sequence IDs are assigned to multiple genomes:")
    for seq, genomes in sorted(conflicts.items()):
        print(f"  {seq}: {', '.join(sorted(genomes))}")

if not duplicate_genomes and not conflicts:
    print("\n✅ All genome names are unique and sequence IDs are uniquely assigned.")
else:
    sys.exit(1)

###################################################################################################

append_files_in_list(REGIONS_HOST, REF_REGIONS_HOST)
append_files_in_list(REGIONS_VIRUSES, REF_REGIONS_VIRUSES)

if not os.path.exists(REF_GTF):

    ###################################################################################################
    # check if gene_id and gene_name are unique across GTF files

    print("Validating GTF files for unique gene_id and gene_name...")
    # Extract gene_id and gene_name from attribute string
    def parse_attributes(attr_string):
        gene_id = gene_name = None
        matches = re.findall(r'(\S+)\s+"([^"]+)"', attr_string)
        for key, val in matches:
            if key == "gene_id":
                gene_id = val
            elif key == "gene_name":
                gene_name = val
        return gene_id, gene_name

    # Dicts to track where each ID was found
    gene_id_to_file = {}
    gene_name_to_file = {}

    # Read GTF files from command line arguments
    gtf_files = GTFS

    for gtf_file in gtf_files:
        with open(gtf_file) as f:
            for line in f:
                if line.startswith("#"):
                    continue
                cols = line.strip().split("\t")
                if len(cols) < 9 or cols[2] != "gene":
                    continue
                attr_string = cols[8]
                gene_id, gene_name = parse_attributes(attr_string)

                if gene_id:
                    if gene_id in gene_id_to_file and gene_id_to_file[gene_id] != gtf_file:
                        print(f"❌ gene_id '{gene_id}' found in both '{gene_id_to_file[gene_id]}' and '{gtf_file}'")
                    gene_id_to_file[gene_id] = gtf_file

                if gene_name:
                    if gene_name in gene_name_to_file and gene_name_to_file[gene_name] != gtf_file:
                        print(f"❌ gene_name '{gene_name}' found in both '{gene_name_to_file[gene_name]}' and '{gtf_file}'")
                    gene_name_to_file[gene_name] = gtf_file

    print("✅ Done checking gene_id and gene_name uniqueness across GTF files.")

###################################################################################################

append_files_in_list(GTFS, REF_GTF)

# read in the samplesheet
# Step 1: Read the tab-delimited file with headers
SAMPLESDF = pd.read_csv(config["samples"], sep="\t", dtype=str).fillna("")

required_columns = [
    "sampleName",
    "groupName",
    "path_to_R1_fastq",
    "path_to_R2_fastq"
]
# Check if all required columns are present
missing_columns = [col for col in required_columns if col not in SAMPLESDF.columns]
if missing_columns:
    print("Headers in the samplesheet:", [f'"{header}"' for header in SAMPLESDF.columns])
    raise ValueError(f"Missing required columns: {', '.join(missing_columns)}")

# Step 2: Confirm that sampleNames are unique
if SAMPLESDF['sampleName'].duplicated().any():
    raise ValueError("Duplicate sampleNames found!")

# SAMPLESDF.set_index(["sampleName"], inplace=False)
SAMPLES = list(SAMPLESDF["sampleName"])

# Step 3: Ensure each sampleName has a non-empty groupName
if (SAMPLESDF['groupName'].str.strip() == "").any():
    raise ValueError("Some sampleNames have empty groupName!")

# Step 4: Check if files in R1 and R2 paths exist and are readable
def check_file(path):
    return path != "" and os.path.isfile(path) and os.access(path, os.R_OK)

SAMPLESDF['R1_exists'] = SAMPLESDF['path_to_R1_fastq'].apply(check_file)
SAMPLESDF['R2_exists'] = SAMPLESDF['path_to_R2_fastq'].apply(check_file)

if not SAMPLESDF['R1_exists'].all():
    raise FileNotFoundError("Some R1 files are missing or not readable.")

# R2 may be missing for single-end, so we'll handle that below

# Step 5: Determine paired-end vs single-end
SAMPLESDF['PEorSE'] = SAMPLESDF['path_to_R2_fastq'].apply(lambda x: x.strip() != "")
SAMPLESDF['PEorSE'] = SAMPLESDF['PEorSE'].apply(lambda x: "PE" if x else "SE")

# Step 6: Create SAMPLENAME2GROUPNAME
SAMPLENAME2GROUPNAME = dict(zip(SAMPLESDF['sampleName'], SAMPLESDF['groupName']))

# Step 7: Create GROUPNAME2SAMPLENAME
from collections import defaultdict
GROUPNAME2SAMPLENAME = defaultdict(list)
for sample, group in zip(SAMPLESDF['sampleName'], SAMPLESDF['groupName']):
    GROUPNAME2SAMPLENAME[group].append(sample)

# Step 8: Create SAMPLENAMEISPE
SAMPLENAMEISPE = dict(zip(SAMPLESDF['sampleName'], SAMPLESDF['PEorSE']))

# Optional: print or return results
print("SAMPLENAME2GROUPNAME:", SAMPLENAME2GROUPNAME)
print("GROUPNAME2SAMPLENAME:", dict(GROUPNAME2SAMPLENAME))
print("SAMPLENAMEISPE:", SAMPLENAMEISPE)


print("SAMPLESDF:\n", SAMPLESDF)
print("SAMPLES:\n", SAMPLES)

DUMMYFILE = join(RESOURCES_DIR, "dummy")
