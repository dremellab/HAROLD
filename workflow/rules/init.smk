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

def _infer_strand_from_rseqc_infer_experiment(file_path, fraction_threshold=0.8):
    """
    Parse an RSeQC/rustqc-format infer_experiment.py output file and return the inferred
    strand ("forward"/"reverse"/"unstranded"). Mirrors
    workflow/scripts/_aggregate_counts_by_strandedness.py's infer_strandedness() -- duplicated
    here (rather than imported) since that script is a standalone CLI tool, not a module, and
    this is used by rustqc_rna_combined's --stranded probe-parsing (qc.smk), a separate
    consumer of the same file format.
    """
    with open(file_path) as f:
        content = f.read()
    if "Fraction of reads explained by" not in content:
        return "unstranded"
    match = re.findall(r"Fraction of reads explained by \"(.*?)\": (\d+\.\d+)", content)
    if not match:
        return "unstranded"
    fractions = {read_type: float(value) for read_type, value in match}
    for key in ("1+-,1-+,2++,2--", "+-,-+"):
        if key in fractions:
            frac = fractions[key]
            if frac > fraction_threshold:
                return "reverse"
            elif frac < (1 - fraction_threshold):
                return "forward"
            else:
                return "unstranded"
    return "unstranded"

###################################################################################

def get_fastqs(wildcards):
    d = dict()
    peorse = SAMPLESDF.loc[SAMPLESDF['sampleName'] == wildcards.sample, 'PEorSE'].values[0]
    # print(f"peorse: {peorse}")
    if peorse == "PE":
        d["R1"] = SAMPLESDF.loc[SAMPLESDF['sampleName'] == wildcards.sample, 'path_to_R1_fastq'].values[0]
        d["R2"] = SAMPLESDF.loc[SAMPLESDF['sampleName'] == wildcards.sample, 'path_to_R2_fastq'].values[0]
    else:
        d["R1"] = SAMPLESDF.loc[SAMPLESDF['sampleName'] == wildcards.sample, 'path_to_R1_fastq'].values[0]
        d["R2"] = DUMMYFILE

    # print(f"sample: {wildcards.sample}")
    # print(f"R1: ##{d['R1']}##")
    # print(f"R2: ##{d['R2']}##")
    return d

###################################################################################

def _get_threads(rule_name, profile_config):
    """
    Return threads for a rule from profile_config.
    Falls back to default if not defined.
    """
    if (
        "set-resources" in profile_config
        and rule_name in profile_config["set-resources"]
        and "threads" in profile_config["set-resources"][rule_name]
    ):
        return profile_config["set-resources"][rule_name]["threads"]
    return profile_config["default-resources"]["threads"]

def _get_runtime(rule_name, profile_config):
    """
    Return the per-attempt base runtime (minutes) for a rule from profile_config.
    Falls back to default if not defined. Meant to be multiplied by Snakemake's
    `attempt` in a rule's `resources:` block so retries (restart-times) get more
    walltime instead of failing identically on every attempt.

    Reads from `retry-base-resources:`, NOT `set-resources:` -- Snakemake's own
    --set-resources/profile mechanism takes precedence over a rule's `resources:`
    block, so a base value placed under `set-resources:` would be re-applied
    unchanged on every attempt and silently defeat this scaling.
    """
    if (
        "retry-base-resources" in profile_config
        and rule_name in profile_config["retry-base-resources"]
        and "runtime" in profile_config["retry-base-resources"][rule_name]
    ):
        return profile_config["retry-base-resources"][rule_name]["runtime"]
    return profile_config["default-resources"]["runtime"]

def _get_mem_mb(rule_name, profile_config):
    """
    Return the per-attempt BASE mem_mb (megabytes) for a rule from profile_config.
    Falls back to default if not defined. Meant to be doubled per Snakemake `attempt`
    in a rule's `resources:` block, for jobs with no prior real-scale memory data that
    risk being OOM-killed on the first try (attempt 1 = base, 2 = 2x, 3 = 4x, 4 = 8x).

    Reads from `retry-base-resources:`, NOT `set-resources:` -- Snakemake's own
    --set-resources/profile mechanism takes precedence over a rule's `resources:`
    block, so a base value placed under `set-resources:` would be re-applied
    unchanged on every attempt and silently defeat this scaling.
    """
    if (
        "retry-base-resources" in profile_config
        and rule_name in profile_config["retry-base-resources"]
        and "mem_mb" in profile_config["retry-base-resources"][rule_name]
    ):
        return profile_config["retry-base-resources"][rule_name]["mem_mb"]
    return profile_config["default-resources"]["mem_mb"]

## Load cluster.json
# with open(config["cluster"]) as json_file:
#     CLUSTER = yaml.safe_load(json_file)


## Create lambda functions to allow a way to insert read-in values
## as rule directives
# getthreads = (
#     lambda rname: int(CLUSTER[rname]["threads"])
#     if rname in CLUSTER and "threads" in CLUSTER[rname]
#     else int(CLUSTER["__default__"]["threads"])
# )
# getmemg = (
#     lambda rname: CLUSTER[rname]["mem"]
#     if rname in CLUSTER and "mem" in CLUSTER[rname]
#     else CLUSTER["__default__"]["mem"]
# )
# getmemG = lambda rname: getmemg(rname).replace("g", "G")

###################################################################################
###################################################################################

# import yaml
# from pathlib import Path

# Locate your cluster profile (relative to workdir or absolute path)
profile_path = join(Path(os.environ["PROFILE"]) , "config.yaml")
with open(profile_path) as f:
    profile_config = yaml.safe_load(f)

# Now profile_config is a normal dict
# pprint(profile_config)
# sys.exit(1)


# print("printing config...")
WORKDIR = os.getcwd()
print(WORKDIR)
configfilepath = join(WORKDIR, "config.yaml") # this is workflow config .. not to be confused with snakemake cluster profile above
try:
    with open(configfilepath, "r") as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"❌ File does not exist: {configfilepath}")
    print(f"❌ Error opening config file: {e}")
    sys.exit(1)
print("Snakemake working directory:", WORKDIR)
# print(config)
# print("end of config")

# resource absolute path
# WORKDIR = config["workdir"]
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
for varname in [
    "WORKDIR", "SCRIPTS_DIR", "RESOURCES_DIR", "FASTAS_GTFS_DIR",
    "STAR_INDEX_DIR", "REF_DIR", "TEMPDIR"
]:
    globals()[varname] = globals()[varname].rstrip(r"\/")

HOST = config["host"].strip()  # hg38 or mm39
ADDITIVES = config["additives"].strip()  # ERCC, BAC16Insert, and/or 4SU1
ADDITIVES = ADDITIVES.replace(" ", "")
VIRUSES = config["viruses"].strip()
VIRUSES = VIRUSES.replace(" ", "")
if HOST != "":
    if ADDITIVES != "":
        HOST_ADDITIVES = HOST + "," + ADDITIVES
    else:
        HOST_ADDITIVES = HOST

    if VIRUSES != "":
        HOST_ADDITIVES_VIRUSES = HOST_ADDITIVES + "," + VIRUSES
        HOST_VIRUSES = HOST + "," + VIRUSES
    else:
        HOST_VIRUSES = HOST
        HOST_ADDITIVES_VIRUSES = HOST_ADDITIVES
else:
    if ADDITIVES != "":
        HOST_ADDITIVES = ADDITIVES
        HOST_ADDITIVES_VIRUSES = ADDITIVES
        HOST_VIRUSES = ""
    else:
        HOST_ADDITIVES = ""
        HOST_ADDITIVES_VIRUSES = ""
        HOST_VIRUSES = ""
    if VIRUSES != "":
        HOST_ADDITIVES_VIRUSES = VIRUSES
        HOST_VIRUSES = VIRUSES
    else:
        raise ValueError("Both host and viruses are not set. Please set at least one of them.")

TRNAS_GTF_MAP = config.get("trnas_gtf", {})
CHRR_GTF_MAP = config.get("chrr_gtf", {})
INCLUDE_TRNAS_GTF_IN_REF = _is_true(config.get("include_trnas_gtf_in_ref", True))
if HOST != "":
    trnas_gtf_name = TRNAS_GTF_MAP.get(HOST, HOST + ".tRNAs." + HOST + "chroms.gtf")
    TRNAS_GTF = trnas_gtf_name if os.path.isabs(trnas_gtf_name) else join(FASTAS_GTFS_DIR, trnas_gtf_name)
    chrr_gtf_name = CHRR_GTF_MAP.get(HOST, HOST + ".chrR.gtf")
    CHRR_GTF = chrr_gtf_name if os.path.isabs(chrr_gtf_name) else join(FASTAS_GTFS_DIR, chrr_gtf_name)
else:
    TRNAS_GTF = ""
    CHRR_GTF = ""

HOST_ADDITIVES_VIRUSES = HOST_ADDITIVES_VIRUSES.split(",")
HOST_VIRUSES = HOST_VIRUSES.split(",")
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
if ADDITIVES != "":
    REGIONS_ADDITIVES = [join(FASTAS_GTFS_DIR, f + ".fa.regions") for f in ADDITIVES.split(",")]
else:
    REGIONS_ADDITIVES = []
GTFS = [join(FASTAS_GTFS_DIR, f + ".gtf") for f in HOST_ADDITIVES_VIRUSES]
if CHRR_GTF != "":
    GTFS.append(CHRR_GTF)
if INCLUDE_TRNAS_GTF_IN_REF and TRNAS_GTF != "":
    GTFS.append(TRNAS_GTF)
FASTAS_REGIONS_GTFS = FASTAS.copy()
FASTAS_REGIONS_GTFS.extend(REGIONS)
FASTAS_REGIONS_GTFS.extend(GTFS)
EGS = join(FASTAS_GTFS_DIR, "effectiveGenomeSizes.tsv")

print("FASTAS_REGIONS_GTFS: ", FASTAS_REGIONS_GTFS)

REF_FA = join(REF_DIR, "ref.fa")
REF_REGIONS = join(REF_DIR, "ref.fa.regions")
REF_REGIONS_HOST = join(REF_DIR, "ref.fa.regions.host")
REF_REGIONS_VIRUSES = join(REF_DIR, "ref.fa.regions.viruses")
REF_REGIONS_ADDITIVES = join(REF_DIR, "ref.fa.regions.additives")
REF_REGIONS_HOST_VIRUSES = join(REF_DIR, "ref.fa.regions.host_viruses")
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
append_files_in_list(REGIONS_HOST + REGIONS_VIRUSES, REF_REGIONS_HOST_VIRUSES)
append_files_in_list(REGIONS_VIRUSES, REF_REGIONS_VIRUSES)
append_files_in_list(REGIONS_ADDITIVES, REF_REGIONS_ADDITIVES)

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
MANIFEST_FILE = config.get("samples")
SAMPLESDF = pd.read_csv(MANIFEST_FILE, sep="\t", dtype=str).fillna("")

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

# Step 3b: Validate batch consistency (if batch column exists, all values must be filled or all empty)
if 'batch' in SAMPLESDF.columns:
    batch_filled = SAMPLESDF['batch'].str.strip() != ""
    has_filled = batch_filled.any()
    has_empty = (~batch_filled).any()
    if has_filled and has_empty:
        raise ValueError("Batch column is inconsistently filled. Either all samples must have a batch value, or all must be empty.")

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
RESULTSDIR = join(WORKDIR, "results")
if not os.path.exists(RESULTSDIR):
    os.mkdir(RESULTSDIR)

DIFFEX_NORMALIZED_COUNTS = str(config.get('diffex_normalized_counts', {}).get('run', 'false')).lower()

def _normalize_species_label(value):
    """Return DiffEx host label (Hs/Mm) from assorted config inputs."""
    if value is None:
        return None
    key = str(value).strip().lower()
    if key in {"hs", "hg38", "grch38", "human"}:
        return "Hs"
    if key in {"mm", "mm39", "mm10", "mouse"}:
        return "Mm"
    return None

DIFFEX_HOST = _normalize_species_label(config.get('host'))

DIFFEX_DEG_GSEA = str(config.get('diffex_deg_gsea', {}).get('run', 'false')).lower()

def _tristate_options(value):
    """Return the list of booleans a tri-state (false/true/both) config value expands to."""
    value = str(value).strip().lower()
    if value == "both":
        return [True, False]
    return [value == "true"]

METHODS = ["limma", "DESeq2", "edgeR"]  # must match diffex deg's own output dir/file naming exactly
CONTRASTS = []
CONTRAST2GROUPS = {}
VARIANTS = {}

if DIFFEX_NORMALIZED_COUNTS == "true" or DIFFEX_DEG_GSEA == "true":
    # use_ercc/use_batch are shared by diffex_normalized_counts and diffex_deg_gsea
    # (config['diffex']) so the aggregate and per-contrast normalizations always agree.
    ERCC_OPTIONS = _tristate_options(config.get('diffex', {}).get('use_ercc', 'false'))
    BATCH_OPTIONS = _tristate_options(config.get('diffex', {}).get('use_batch', 'false'))
    BATCH_COLUMN = str(config.get('diffex', {}).get('batch_column', 'batch'))

    if True in BATCH_OPTIONS:
        # A single-level batch factor makes limma's design matrix blow up with an
        # opaque "contrasts can be applied only to factors with 2 or more levels"
        # error deep inside the diffex container, only after the DAG has already
        # spent compute on everything upstream of normalized_counts/diffex_deg.
        # Catch it here instead, at config-parse time (covers dryrun too).
        if BATCH_COLUMN not in SAMPLESDF.columns:
            raise ValueError(
                f"diffex.use_batch is 'true'/'both' in config.yaml, but batch_column "
                f"'{BATCH_COLUMN}' is not a column in the samplesheet."
            )
        if DIFFEX_NORMALIZED_COUNTS == "true":
            all_batches = sorted(SAMPLESDF[BATCH_COLUMN].dropna().unique())
            if len(all_batches) < 2:
                raise ValueError(
                    f"diffex_normalized_counts.run is 'true' and diffex.use_batch is 'true'/'both', but "
                    f"'{BATCH_COLUMN}' only has {len(all_batches)} distinct value(s) ({all_batches}) across "
                    f"all samples -- batch correction requires at least 2 batches. Either fix "
                    f"'{BATCH_COLUMN}' in the samplesheet, or set diffex.use_batch: false in config.yaml."
                )

    for e in ERCC_OPTIONS:
        for b in BATCH_OPTIONS:
            # Always tag both segments (not just the ones with a "both" tri-state),
            # so directory names alone always show whether ERCC/batch were applied
            # rather than only when use_ercc/use_batch is set to "both".
            parts = ["w_ercc" if e else "wo_ercc", "w_batch" if b else "wo_batch"]
            VARIANTS["_".join(parts)] = (e, b)

if DIFFEX_DEG_GSEA == "true":
    CONTRASTS_FILE = config.get('diffex_deg_gsea', {}).get('contrasts')
    if not CONTRASTS_FILE or not os.path.isfile(CONTRASTS_FILE):
        raise FileNotFoundError(
            f"diffex_deg_gsea.run is set to true in config.yaml, so a contrasts.tsv file is required, "
            f"but none was found at diffex_deg_gsea.contrasts: '{CONTRASTS_FILE}'. "
            f"Either fix that path in config.yaml, or supply one with 'harold --contrasts=/path/to/contrasts.tsv ...' "
            f"to copy it into the workdir."
        )
    CONTRASTSDF = pd.read_csv(CONTRASTS_FILE, sep="\t", dtype=str).fillna("")

    contrasts_required_columns = ["group1", "group2"]
    missing_contrasts_columns = [col for col in contrasts_required_columns if col not in CONTRASTSDF.columns]
    if missing_contrasts_columns:
        print("Headers in the contrasts file:", [f'"{header}"' for header in CONTRASTSDF.columns])
        raise ValueError(f"Missing required columns in contrasts file: {', '.join(missing_contrasts_columns)}")

    if CONTRASTSDF[["group1", "group2"]].duplicated().any():
        raise ValueError("Duplicate (group1, group2) rows found in contrasts file!")

    known_groups = set(SAMPLESDF['groupName'])
    unknown_groups = (set(CONTRASTSDF['group1']) | set(CONTRASTSDF['group2'])) - known_groups
    if unknown_groups:
        raise ValueError(f"Contrasts file references groupName(s) not present in the samplesheet: {', '.join(unknown_groups)}")

    CONTRASTS = [f"{r.group1}_vs_{r.group2}" for r in CONTRASTSDF.itertuples()]
    CONTRAST2GROUPS = {f"{r.group1}_vs_{r.group2}": (r.group1, r.group2) for r in CONTRASTSDF.itertuples()}

    if True in BATCH_OPTIONS:
        # Same rationale as the normalized_counts check above, but per-contrast:
        # diffex_deg only sees the group1/group2 samples for a given contrast, so
        # the whole-cohort batch column can have 2+ levels while a specific
        # contrast's samples still collapse to a single one.
        bad_contrasts = []
        for contrast, (group1, group2) in CONTRAST2GROUPS.items():
            contrast_batches = sorted(
                SAMPLESDF.loc[SAMPLESDF['groupName'].isin([group1, group2]), BATCH_COLUMN].dropna().unique()
            )
            if len(contrast_batches) < 2:
                bad_contrasts.append(f"{contrast} ({BATCH_COLUMN}={contrast_batches})")
        if bad_contrasts:
            raise ValueError(
                f"diffex_deg_gsea.run is 'true' and diffex.use_batch is 'true'/'both', but these "
                f"contrast(s) only see a single distinct '{BATCH_COLUMN}' value among their group1/group2 "
                f"samples, so batch correction isn't possible for them: {'; '.join(bad_contrasts)}. Either "
                f"fix '{BATCH_COLUMN}' in the samplesheet for these groups, or set diffex.use_batch: false."
            )

USE_INFER_STRANDEDNESS = str(config.get("use_infer_strandedness", "true")).lower()
INFER_FRACTION_THRESHOLD = config.get("infer_strandedness_threshold", 0.8)
STRANDEDNESS_COLUMN = config.get("strandedness_column", "strandedness")
if STRANDEDNESS_COLUMN in SAMPLESDF.columns:
    # Normalize user-provided labels so validation is case-insensitive.
    SAMPLESDF[STRANDEDNESS_COLUMN] = SAMPLESDF[STRANDEDNESS_COLUMN].astype(str).str.strip().str.lower()
if USE_INFER_STRANDEDNESS == "false":
    # samplesdf then needs to have a column called "strandedness"
    if STRANDEDNESS_COLUMN not in SAMPLESDF.columns:
        raise ValueError(f"Column '{STRANDEDNESS_COLUMN}' not found in samplesheet but is required when use_infer_strandedness is set to False.")
    # check if values in that column are valid
    valid_values = {"unstranded", "forward", "reverse"}
    invalid_values = set(SAMPLESDF[STRANDEDNESS_COLUMN].unique()) - valid_values
    if invalid_values:
        raise ValueError(f"Invalid values in column '{STRANDEDNESS_COLUMN}': {', '.join(invalid_values)} ... Valid values are: {', '.join(valid_values)}.")
