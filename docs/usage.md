# 🧭 Using HAROLD on Rivanna

Once your environment is configured and HAROLD is available as a command, the pipeline can typically be executed in **three main steps**. These steps correspond to the standard workflow of initialization, validation, and execution. Before starting, make sure you have:

1. A **sample sheet (manifest)** that lists your input FASTQ files and sample identifiers.
2. A known **reference combination**, including the host genome, any additives, and the viral genomes you want to include.

Each run of HAROLD is controlled through the `--runmode` option, which determines what the pipeline will do.

---

## Step 1: Initialization (`runmode=init`)

The initialization step prepares the working directory and configuration for the analysis. When you run HAROLD in initialization mode, it will:

- Create a new **output directory** where all results and logs will be stored.
- Copy the required pipeline templates and configuration files into that directory.
- Generate a new `config.yaml` file in the working directory based on your inputs.

### Required arguments

- `--workdir` or `-w`: The absolute or relative path to the directory where HAROLD will create output files.
- `--host` or `-g`: The host genome to use (`hg38` for human or `mm39` for mouse).
- `--additives` or `-a`: Additive control sequences such as `ERCC` or `BAC16Insert`. Multiple values can be supplied as a comma-separated list.
- `--viruses` or `-v`: One or more virus accessions (for example, `NC_009333.1` for KSHV or `NC_045512.2` for SARS-CoV-2). Multiple accessions can also be supplied as a comma-separated list.
- `--manifest` or `-s`: The path to the sample manifest file, usually a tab-separated file listing sample names and FASTQ file paths.

### Example command

```bash
harold -w=/scratch/$USER/harold_test -m=init \
  --host=hg38 \
  --additives=ERCC,BAC16Insert \
  --viruses=NC_009333.1,NC_045512.2 \
  --manifest=/project/$USER/samples.tsv
```

After this command runs successfully, HAROLD creates the working directory, populates it with configuration files, and prepares it for analysis.

---

## Step 2: Dry Run (`runmode=dryrun`)

The dry run step is used to verify that the pipeline is configured correctly and that Snakemake can execute all necessary rules without errors. It does **not** run the actual computations but instead performs a dependency and syntax check of the workflow.

To perform a dry run, specify the same working directory and set the run mode to `dryrun`:

```bash
harold -w=/scratch/$USER/harold_test -m=dryrun
```

During this step, HAROLD checks the configuration, paths, and dependencies. If everything is correctly configured, it will display a list of Snakemake rules that would be executed if the pipeline were run for real. This step ensures that all input files exist and that the selected reference and manifest are compatible.

If errors are detected, HAROLD provides informative messages about missing files or invalid parameters so they can be fixed before running the full workflow.

---

## Step 3: Execution (`runmode=run`)

Once the dry run completes successfully, you can proceed to the execution phase. In this step, HAROLD submits all required Snakemake jobs to the **SLURM scheduler** on Rivanna. The pipeline will handle job dependencies, memory requests, and resource allocations automatically.

To start the full analysis, run:

```bash
harold -w=/scratch/$USER/harold_test -m=run
```

The workflow will now begin executing on Rivanna’s compute nodes. Each rule (step of the pipeline) will produce a corresponding log file stored under the `logs/` subdirectory within your working directory. You can monitor progress by examining these log files or by using standard SLURM commands such as `squeue -u $USER` to check job status.

When the pipeline finishes, the working directory will contain organized subfolders for `counts`, `alignment`, `logs`, and `reports`. The main outputs include raw count matrices, sample manifest copies, BAM/BAI alignment files, bigWig coverage tracks, and the MultiQC report summarizing quality control results.

---

## Summary

Running HAROLD typically involves three steps: **initialization**, **dry-run validation**, and **execution**. Together, these steps make sure the configuration is correct, resources are available, and the final analysis can proceed without interruption. Following this workflow ensures reproducibility and consistency in large-scale RNA-seq processing on the Rivanna HPC environment.
