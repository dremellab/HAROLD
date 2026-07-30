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
- `--additives` or `-a`: Additive control sequences such as `ERCC`, `BAC16Insert`, or `4SU1`. Multiple values can be supplied as a comma-separated list.
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

### Tracking run state

Every `runlocal`/`run` invocation writes a state marker and JSON status sidecar to `WORKDIR` so you can check pipeline status without digging through logs:

- **State marker** — exactly one of `pipeline.running`, `pipeline.completed`, `pipeline.failed`, or `pipeline.canceled` exists in `WORKDIR` at any time, replaced as the run progresses. While a run is active (`run` on SLURM or `runlocal`), `pipeline.running` is periodically rewritten with a live progress summary (steps complete, percent done, steps remaining) parsed from Snakemake's own step-completion output, so `cat $WORKDIR/pipeline.running` gives an at-a-glance status. On success, `pipeline.completed` carries the same summary showing the final tally (100% done, 0 remaining) rather than being left empty; on failure, `pipeline.failed` preserves whatever progress was last recorded, so you can see how far the run got before failing.
- **`pipeline.status.json`** — a structured sidecar with `state`, `reason`, `runmode`, `slurm_job_id`, `host`, and `timestamp_utc`, updated at submission, success, failure, and on cancellation (SIGTERM/SIGINT, e.g. `scancel`).

```bash
cat $WORKDIR/pipeline.running        # live progress, while a run is active
cat $WORKDIR/pipeline.completed      # final tally, once finished successfully
cat $WORKDIR/pipeline.status.json    # structured status snapshot
```

`harold` command output itself is also leveled (`INFO`/`STEP`/`OK`/`WARN`/`ERROR`/`NEXT`), with `NEXT` lines suggesting the next command to run after `init`, `dryrun`, and job submission.

---

## Step 4 (Optional): DEG & GSEA

HAROLD can run differential expression (DEG) and gene set enrichment analysis (GSEA) directly on its count matrices via DiffEx. This step is **optional** and requires a contrasts manifest.

To enable it:
1. Create a `contrasts.tsv` file (tab-delimited, `group1`/`group2` columns) listing which `groupName` pairs from your `samples.tsv` to compare. Each row is one contrast; `group1`/`group2` must match `groupName` values in your `samples.tsv` exactly.

   ```text
   group1	group2
   Treatment	Control
   Treatment_2h	Control_2h
   Treatment_6h	Control_6h
   ```

2. Supply it at `init` time with `--contrasts` or `-x` (it is copied to `WORKDIR/contrasts.tsv`), or add it to an already-initialized workdir and re-run `init`:
   ```bash
   harold -w=/scratch/$USER/harold_test -m=init \
     --host=hg38 \
     --additives=ERCC,BAC16Insert \
     --viruses=NC_009333.1,NC_045512.2 \
     --manifest=/project/$USER/samples.tsv \
     --contrasts=/project/$USER/contrasts.tsv
   ```
3. Set `diffex_deg_gsea: true` in `config.yaml`.

Per contrast, HAROLD runs `diffex deg` (limma, DESeq2, and edgeR) against the counts matrix, then `diffex gsea` on each method's ranked gene list. ERCC/batch handling is controlled by the shared `diffex:` config block (`use_ercc`/`use_batch`, tri-state `false`/`true`/`both`), which also governs the aggregate `diffex_normalized_counts` step so the two never disagree on how the matrix was normalized; `both` runs a given step once per variant and keeps all of them. See [Outputs: DEG and GSEA](outputs.md#deg-and-gsea-diffex-integration) for the full output layout.

If `use_ercc` is `true` or `both`, also set `ercc_mix` (`1` or `2`) in the same `diffex:` block to match whichever ERCC spike-in mix was actually added to your libraries during prep. ERCC spike-ins ship as two mixes containing the same 92 synthetic transcripts at different known relative concentrations — using the wrong mix number here doesn't cause an error, it just silently normalizes against the wrong expected concentrations, so double-check it against your wet-lab protocol rather than leaving it at the default.

---

## Step 5 (Optional): S3 Deposition

HAROLD can automatically upload results to Amazon S3 for cloud storage and sharing. This step is **optional** and requires prior configuration.

To enable S3 transfer:
1. Ensure you have AWS credentials and access to an S3 bucket (see [S3/Globus Access Guide](https://dremellab.github.io/howtos/guides/s3-globus-access/s3_globus_access_guide.html) if needed)
2. Update your `config.yaml`:
   ```yaml
   push_to_s3: true
   s3_sample_set_name: "my_exp_batch1"  # Choose a meaningful name
   ```
3. Re-run the pipeline (S3 transfer will execute automatically upon successful completion of all other stages)

See the [S3 Configuration Guide](s3_configuration.md) for detailed instructions on setup, cost estimation, storage classes, and troubleshooting.

---

## Monitoring SLURM jobs and locating rule-specific logs

While `harold -m run` is active, the driver submits one head job plus hundreds of per-rule batch jobs to SLURM. For a detailed status view, use the explicit Rivanna `squeue` binary with a custom format string:

```bash
/opt/slurm/current/bin/squeue -u <computing_id> \
  -o "%.18i %.50j %.8u %.2t %.10M %.6D %.6C %R"
```

This prints the job ID, Snakemake-generated job name, user, state, elapsed time, nodes, cores, and pending reason/host. The columns make it easy to spot jobs that are queued (`PD`), actively running (`R`), or already finished.

Every SLURM task writes a dedicated log file under `$WORKDIR/logs`, grouped by rule and sample. A typical tree looks like:

```
logs/
├── rule_cutadapt/Uninf_RLIG1_R2/7130520.log
├── rule_star_align_two_pass/Inf_NTC_R1/7130711.log
├── rule_rustqc_rna_combined/Uninf_RLIG1_R2/7130807.log
└── ...
```

To jump straight to the stdout/stderr for a specific SLURM job ID, search the log tree:

```bash
# Example for jobid 7130807
find $WORKDIR/logs -name "*7130807*"
```

Open the matching `.log` to see the exact command, module setup, and any errors for that Snakemake rule. This workflow—`squeue` to identify the job followed by `find` in `logs/`—is the fastest way to debug failed or stalled tasks.

---

## Summary

Running HAROLD typically involves three steps: **initialization**, **dry-run validation**, and **execution**. Together, these steps make sure the configuration is correct, resources are available, and the final analysis can proceed without interruption. Following this workflow ensures reproducibility and consistency in large-scale RNA-seq processing on the Rivanna HPC environment.
