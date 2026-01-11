# ⚙️ Prerequisites for Running HAROLD on Rivanna

Before running HAROLD, ensure that your computing environment is correctly configured and that you have access to the University of Virginia’s high-performance computing (HPC) system, **Rivanna**. HAROLD is tested and supported exclusively on Rivanna.

---

## 1. Obtain a Rivanna Account

To access Rivanna, you must first have an active UVA computing account. Visit the [Research Computing website](https://www.rc.virginia.edu/) for detailed instructions on creating an account and requesting HPC access. You’ll receive a username and credentials that allow you to log in via SSH.

---

## 2. Connect via UVA VPN

Access to Rivanna requires connecting to the UVA network through the **UVA VPN**. It is recommended to use the **VPN Anywhere** profile or a better connection profile to ensure uninterrupted SSH access. Instructions for installing and configuring the VPN are also available on the UVA Research Computing site.

---

## 3. Accessing Rivanna from the Command Line

You will need a terminal interface (such as Terminal on macOS, Command Prompt or PowerShell on Windows, or any Linux shell). This environment allows you to use SSH to connect to Rivanna and run the HAROLD command-line interface.

Once the VPN connection is active, open your terminal and log in to Rivanna:

```bash
ssh <your_computing_id>@login.hpc.virginia.edu
```

---

## 4. Load the Mamba Environment

Once connected to Rivanna, load the shared configuration and activate the **pipelines** conda environment used by HAROLD.

```bash
# Load mamba and activate environment
source /project/dremel_lab/scripts/.sh_common
mamba activate pipelines
```

This prepares the environment with all required dependencies, including Snakemake, Python, and the HAROLD executable.

---

## 5. Verify HAROLD Installation

Typing `harold` by itself will not display the full help message. To confirm that HAROLD is properly installed, use the `--help` flag:

```bash
harold --help
```

When executed correctly, you should see output similar to the following:

```
##########################################################################################

Welcome to HAROLD
This is a basic RNAseq pipeline to get counts matrix for host + viral proteins.

HAROLD is only tested on Rivanna (https://www.rc.virginia.edu).
Please edit the files in config/unknown/ & config.yaml for compatibility with your
computing environment

##########################################################################################

HAROLD can be used to detect and count transcripts in hosts and viruses.

Here is the list of hosts and viruses that are currently supported:

HOSTS:
  * hg38          [Human]
  * mm39          [Mouse]

ADDITIVES:
  * ERCC          [External RNA Control Consortium sequences]
  * BAC16Insert   [insert from rKSHV.219-derived BAC clone of the full-length KSHV genome]

VIRUSES:
  * NC_007605.1   [Human gammaherpesvirus 4 (Epstein-Barr virus)]
  * NC_006273.2   [Human betaherpesvirus 5 (Cytomegalovirus )]
  * NC_001664.4   [Human betaherpesvirus 6A (HHV-6A)]
  * NC_000898.1   [Human betaherpesvirus 6B (HHV-6B)]
  * NC_001716.2   [Human betaherpesvirus 7 (HHV-7)]
  * NC_009333.1   [Human gammaherpesvirus 8 (KSHV)]
  * NC_045512.2   [Severe acute respiratory syndrome (SARS)-related coronavirus]
  * MN485971.1    [HIV from Belgium]
  * NC_001806.2   [Human alphaherpesvirus 1 (Herpes simplex virus type 1) (strain 17)]
  * KT899744.1    [HSV-1 strain KOS]
  * MH636806.1    [MHV68 (Murine herpesvirus 68 strain WUMS)]

##########################################################################################

USAGE:
  harold -w/--workdir=<WORKDIR> -m/--runmode=<RUNMODE>

Required Arguments:
1.  WORKDIR     : [Type: String] Absolute or relative path to the output folder with write permissions.
2.  RUNMODE     : [Type: String] Valid options:
    * init      : initialize workdir
    * dryrun    : dry run snakemake to generate DAG
    * run       : run with slurm
    * runlocal  : run without submitting to sbatch
    * unlock    : unlock WORKDIR if locked by snakemake (use with caution)
    * reconfig  : recreate config file in WORKDIR
    * reset     : DELETE workdir dir and re-init it (debugging)
    * printbinds: print singularity binds (paths)
    * local     : same as runlocal

Optional Arguments:
--host|-g       : supply host genome (hg38 or mm39) (--runmode=init only)
--additives|-a  : supply comma-separated list of additives (ERCC or BAC16Insert) (--runmode=init only)
--viruses|-v    : supply comma-separated list of viruses (--runmode=init only)
--manifest|-s   : absolute path to samples.tsv (--runmode=init only)
--help|-h       : print this help

Example commands:
  harold -w=/my/output/folder -m=init
  harold -w=/my/output/folder -m=dryrun
  harold -w=/my/output/folder -m=run

##########################################################################################

VersionInfo:
  python          : 3.11
  snakemake       : 9.8.1
  pipeline_home   : /sfs/ceph/project/dremel_lab/workflows/pipelines/HAROLD/v1.1.0
  git commit/tag  : f8b62bb1596e2c91587921849ab47f3e8b2a8ab8 v1.1.0
  pipeline version: v1.1.0
  cluster_name    : shen

##########################################################################################
```

If you see this output, HAROLD is ready to run.

---

## 6. Shared Apptainer Images and Cache Layout

HAROLD uses Apptainer/Singularity containers for every Snakemake rule. To reduce duplicate pulls, the wrapper now points to the lab-managed image repository at `/project/dremel_lab/workflows/singularity_images` by default. All cached SIF files in that directory are shared read-only across Rivanna users.

During runtime HAROLD also prepares a per-user scratch workspace under `/scratch/$USER/singularity/`:

- `cache/` – Apptainer layer cache used while pulling from Docker/OCI registries.
- `tmp/` – temporary directory exported as `APPTAINER_TMPDIR`/`SINGULARITY_TMPDIR`.
- `images/` – default pull location (`APPTAINER_PULLDIR`) when a container does not already exist in the shared SIF directory.

When you run `harold --runmode init`, the wrapper now echoes the locations it will use, for example:

```
Singularity Cache Dir: /scratch/cud2td/singularity/cache
Singularity Tmp Dir: /scratch/cud2td/singularity/tmp
Singularity Pull Dir: /scratch/cud2td/singularity/images
```

The `Singularity Image Dir` line that appears in later Snakemake logs refers to the `--sifdir` setting (the shared `/project/dremel_lab/workflows/singularity_images` by default). The printed “Pull Dir” is the scratch location where new `.sif` files will be written when an image is missing from that shared tree, so you should always see three separate directories: cache, tmp, and pull.

If a requested SIF is missing from the shared repository, the wrapper prints a warning and Apptainer automatically pulls it into your scratch cache when the rule executes. You can override the defaults with:

- `--sifdir /path/to/sif` to point at a different image directory (for example, a personal mirror).
- `--singcache /path/to/cache` to control where cache layers and temporary files are written.

The wrapper also honors pre-set environment variables (`SINGULARITY_CACHEDIR`, `SINGULARITY_TMPDIR`, and `SINGULARITY_PULLFOLDER`) so site administrators can direct HAROLD to lab-managed storage via login scripts.

When the shared `/project/.../singularity_images` tree is used for read-only access, new pulls automatically fall back to `/scratch/$USER/singularity/images`, ensuring jobs can still run without trying to write to the shared mount. The runtime warning

```
Singularity image docker://<repo>:<tag> will be pulled.
```

is expected the first time each container is staged to scratch.

On compute nodes, the jobscript reuses the shared image directory when available and transparently falls back to `/scratch/$USER/singularity/sif` if the shared path is not accessible, ensuring every rule can still run.

---

## 7. Reference bundle created inside each work directory

When you run `harold -m init`, the wrapper stages a full copy of `config/` plus your `samples.tsv` under the new working directory. The first Snakemake jobs (`create_index`, `gtf_to_bed`, and friends) then build a composite reference bundle under:

```
$WORKDIR/ref/
├── ref.fa                         # combined host + additives + virus FASTA
├── ref.fa.regions                 # BED-like regions file used for per-genome splitting
├── ref.fa.regions.host(.*)        # host-only slices for BAM splitting
├── ref.fa.regions.viruses(.*)     # virus-only slices
├── ref.gtf                        # concatenated transcript annotation
├── ref.fixed.gtf                  # cleaned-up GTF that STAR/Snakemake consume
├── ref.genes.genepred(_w_geneid)  # formats used by RSeQC
├── ref.genes.(bed|bed12)          # BED exports for GTF → BED jobs
└── STAR_no_GTF/                   # STAR genome index
```

These files are built entirely inside the work directory so multiple HAROLD runs cannot interfere with each other. Re-running `harold -m dryrun` or `harold -m run` in the same directory will skip any reference assets that already exist unless you remove the files manually or use `harold -m reset`.

---

## 8. Understanding Snakemake dry-run output

`harold -m dryrun` invokes Snakemake with `--dry-run`, `--printshellcmds`, and Rivanna’s profile so you can inspect the entire DAG without consuming compute time. A typical snippet looks like:

```
Need to rerun job cutadapt because of missing output required by all.
Need to rerun job create_index because of missing output required by all.
Singularity image docker://seqinfomics/rseqc:4.0.0 will be pulled.
FILE /path/to/workdir/ref/ref.fa does not exist! Creating it!
Job stats:
job                    count
---------------------  -----
cutadapt                   8
create_index               1
...
total                    162
```

Key things to know:

- Every `Need to rerun job ...` line simply means the corresponding rule has missing outputs in this new work directory. That is expected on the first run because nothing has been produced yet.
- The `FILE ... does not exist! Creating it!` messages come from HAROLD helper scripts that pre-create composite files such as `ref.fa`, `ref.fa.regions`, and the derived `.gtf` artifacts listed above.
- `Singularity image ... will be pulled.` is informative only; no containers are fetched during a dry run. The warning tells you which rules will contact Docker Hub the first time you do a real `run`/`runlocal`.
- The final “Job stats” table is Snakemake’s count of how many times each rule would execute. This lets you gauge how much work is queued before launching a real run.

Because `--dry-run` never touches data, you can use it freely after editing `config.yaml` or `samples.tsv` to confirm HAROLD recognizes the changes. Once you are satisfied with the dry-run summary, re-run `harold -m run` (or `runlocal`) from the same work directory to start the actual workflow.
