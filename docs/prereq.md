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
source /standard/dremel_lab/scripts/.sh_common
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
  pipeline_home   : /sfs/ceph/standard/dremel_lab/workflows/pipelines/HAROLD/v1.0.0
  git commit/tag  : 2156e6eb4b142f74dc5ae2d65f3bca4159574eda v1.0.0
  pipeline version: v1.0.0
  cluster_name    : shen

##########################################################################################
```

If you see this output, HAROLD is ready to run.
