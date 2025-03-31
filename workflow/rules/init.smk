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
append_files_in_list(REGIONS_HOST, REF_REGIONS_HOST)
append_files_in_list(REGIONS_VIRUSES, REF_REGIONS_VIRUSES)
append_files_in_list(GTFS, REF_GTF)

# read in the samplesheet
# Step 1: Read the tab-delimited file with headers
df = pd.read_csv(config["samples"], sep="\t", dtype=str).fillna("")

required_columns = [
    "sampleName",
    "groupName",
    "path_to_R1_fastq",
    "path_to_R2_fastq"
]
# Check if all required columns are present
missing_columns = [col for col in required_columns if col not in df.columns]
if missing_columns:
    print("Headers in the samplesheet:", [f'"{header}"' for header in df.columns])
    raise ValueError(f"Missing required columns: {', '.join(missing_columns)}")

# Step 2: Confirm that sampleNames are unique
if df['sampleName'].duplicated().any():
    raise ValueError("Duplicate sampleNames found!")

# Step 3: Ensure each sampleName has a non-empty groupName
if (df['groupName'].str.strip() == "").any():
    raise ValueError("Some sampleNames have empty groupName!")

# Step 4: Check if files in R1 and R2 paths exist and are readable
def check_file(path):
    return path != "" and os.path.isfile(path) and os.access(path, os.R_OK)

df['R1_exists'] = df['path_to_R1_fastq'].apply(check_file)
df['R2_exists'] = df['path_to_R2_fastq'].apply(check_file)

if not df['R1_exists'].all():
    raise FileNotFoundError("Some R1 files are missing or not readable.")

# R2 may be missing for single-end, so we'll handle that below

# Step 5: Determine paired-end vs single-end
df['is_paired_end'] = df['path_to_R2_fastq'].apply(lambda x: x.strip() != "")


# Step 6: Create SAMPLENAME2GROUPNAME
SAMPLENAME2GROUPNAME = dict(zip(df['sampleName'], df['groupName']))

# Step 7: Create GROUPNAME2SAMPLENAME
from collections import defaultdict
GROUPNAME2SAMPLENAME = defaultdict(list)
for sample, group in zip(df['sampleName'], df['groupName']):
    GROUPNAME2SAMPLENAME[group].append(sample)

# Step 8: Create SAMPLENAMEISPE
SAMPLENAMEISPE = dict(zip(df['sampleName'], df['is_paired_end']))

# Optional: print or return results
print("SAMPLENAME2GROUPNAME:", SAMPLENAME2GROUPNAME)
print("GROUPNAME2SAMPLENAME:", dict(GROUPNAME2SAMPLENAME))
print("SAMPLENAMEISPE:", SAMPLENAMEISPE)
