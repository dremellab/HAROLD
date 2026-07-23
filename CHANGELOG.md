# Changelog

All notable changes to this project will be documented in this file.

## [dev]

### ⚠️ Breaking Changes
- **Shared `diffex` config block:** `use_ercc`, `ercc_mix`, `use_batch`, `batch_column`, and `genes_selection` moved out of `diffex_normalized_counts` and `diffex_deg_gsea` into one shared `diffex:` block, so the aggregate normalized-counts step and the per-contrast DEG/GSEA step can no longer disagree on ERCC/batch handling. The now-unused `diffex_normalized_counts.host` key was also removed (host was already sourced from the top-level `host:` config). As a result, `diffex_normalized_counts` output moved from `counts/normalized_counts/normalize.html` to `counts/normalized_counts/{variant}/normalize.html`, mirroring the DEG/GSEA variant layout, since `diffex.use_ercc`/`use_batch: both` now expands the aggregate step per-variant too. Update existing `config.yaml` files to the new schema (see #51).

### Added
- **Downsample BAM before RSeQC TIN calculation:** New `downsample_bam_for_tin` rule caps the BAM fed into `tin.py` at `rseqc_tin_downsample_reads` primary-mapped reads (config; default 50,000,000, counted the `samtools flagstat` way — each mate counted separately, so ~25,000,000 pairs for paired-end data) — samples above that threshold are randomly downsampled with `samtools view -s`, which keeps read pairs together (no singleton mates), before every other TIN output. This bounds `tin.py`'s runtime, which scales poorly with read depth, without changing any TIN output filenames or the `aggregate_tin.tsv` schema.
- **Additive/spike-in mapped reads in `alignment_summary.tsv`:** New `{additive}_mapped` column per configured additive (e.g. `ERCC_mapped`, `BAC16Insert_mapped`, `4SU1_mapped`), reporting primary BAM alignments to each additive/spike-in reference — mirrors the existing per-virus `{virus}_mapped` columns. Previously these reads were only visible folded into STAR's overall `reads_mapped_to_assembly` figure ([#52](https://github.com/dremellab/HAROLD/issues/52)).
- **`4SU1` additive documented:** `4SU1` (a synthetic spike-in control for 4-thiouridine metabolic-labeling RNA-seq, already usable via the generic additives mechanism) is now listed alongside `ERCC`/`BAC16Insert` in `harold --help`, `docs/prereq.md`, `docs/inputs.md`, `docs/usage.md`, `docs/outputs.md`, and `config/config.yaml` ([#53](https://github.com/dremellab/HAROLD/issues/53)).
- **Guard against submitting/unlocking into an already-running workdir:** `harold -m=run`/`runlocal`/`unlock` now refuse to proceed (and point at the file) if `${WORKDIR}/pipeline.running` already exists, since two runs racing on the same workdir/state (or unlocking a genuinely still-active run) can corrupt pipeline state. `dryrun` still runs normally against such a workdir (it's read-only), but now warns prominently at the end if a run may already be in progress, and skips the `Submit run with: harold -m=run` hint in that case ([#54](https://github.com/dremellab/HAROLD/issues/54)).

### Changed
- **Final-state `pipeline.*` progress reporting:** `pipeline.completed` now reports the final step tally (`N / N steps complete (100%)`, `Remaining: 0 steps`) instead of being an empty marker file, matching the live format `pipeline.running` already used. `pipeline.failed` now preserves the last known progress snapshot instead of being emptied, so a failed run shows how far it got before failing. `runlocal` (previously untracked) now gets the same live progress monitoring as SLURM `run` jobs, via a tee'd Snakemake log.
- **`diffex` container bumped `0.5.2` → `0.5.5`:** picks up the DEG UpSetR crash fix (v0.5.3) and the GSEA `+Inf`/`-Inf` rank-clamp fix (v0.5.5, [dremellab/DiffEx#41](https://github.com/dremellab/DiffEx/pull/41)) that HAROLD's own `_sanitize_rnk.py` pre-processing step was working around. Switched to `docker://seqinfomics/diffex:0.5.5` (Docker Hub) rather than `ghcr.io/dremellab/diffex`, since no image newer than `0.5.2` has been published to GHCR ([dremellab/DiffEx#40](https://github.com/dremellab/DiffEx/issues/40)).

### Fixed
- **`fastq_validate_sample` OOM on large FASTQ files:** the rule had no memory override, so it used the pipeline-wide 40 GB default. `fastQValidator` runs unconditionally before `cutadapt` and blocks it on failure, so an OOM here (observed killed at ~40 GB validating a ~20-22 GB gzip R1/R2 pair) silently blocks the whole sample with no config workaround. Bumped to 120 GB (`config/rivanna/config.yaml`, matching the existing `cutadapt` allocation for the same files).

## [2.0.0]

### ⚠️ Breaking Changes
- **Config key renamed:** `infer_strandedness` → `use_infer_strandedness`. Update existing config files to use the new key name for clarity (true = use inferred values, false = use manifest values).

### Added
- DEG and GSEA pipeline stage — New optional `diffex_deg_gsea` stage driven by a `contrasts.tsv` manifest (`harold --contrasts/-x`); runs DiffEx DEG (limma/DESeq2/edgeR) per contrast/variant/method followed by GSEA, with tri-state ERCC/batch variant expansion, a shared MSigDB cache warm-up, and `.rnk` sanitization for +/-Inf scores
- Pipeline run-state tracking — `harold` now writes `pipeline.{running,completed,failed,canceled}` markers and a `pipeline.status.json` sidecar to WORKDIR, updated on `runlocal`/`run` start, success, failure, and Slurm cancellation (SIGTERM/SIGINT trap)
- Live progress monitoring — Slurm head job now tails Snakemake's step-completion output and writes a human-readable progress summary into `pipeline.running`
- Structured CLI logging — `harold` output now uses leveled log helpers (`INFO`/`STEP`/`OK`/`WARN`/`ERROR`/`NEXT`) with next-step hints after `init`, `dryrun`, and job submission
- S3 deposit feature — Pipeline outputs can now be transferred to S3 buckets (GitHub #44)
- Alignment summary report — New QC report in the workflow
- FASTQ validation gating — Cutadapt can now be gated behind FASTQ validation
- Host-specific GTF support — Configuration now supports host-specific tRNA/chrR GTF files (removes repeats GTF wiring)

### Changed
- S3 namespace hierarchy — Updated `s3_transfer_harold.py` to include pipeline-name in S3 path hierarchy (`_HTS/HAROLD/sample_set/...`) for consistency with Chroma 2; added `s3_pipeline_name` config key (default: `HAROLD`)
- rseqc_tin runtime — Increased to 36 hours for longer-running samples
- Repeats GTF configurability — Now a configurable reference, included in ref.gtf by default
- Default reference path — Updated fasta_gtf reference path to `/project/dremel_lab/workflows/reference_data/fasta_gtf`
- Manifest initialization — Strand values now normalized to lowercase during manifest parsing
- Documentation clarification — Improved strandedness documentation to clarify that HAROLD always infers strandedness and reports it; the config option controls only whether inferred or manifest values are used for count extraction
- S3 documentation accuracy — Corrected `s3_configuration.md`'s "Files Transferred to S3" table, which listed peak files, ataqv data, and tRNA/Tn5 outputs that HAROLD doesn't produce; documented the previously-missing SJ, DEG/GSEA, and normalized-counts transfers instead
- SLURM resource tuning — Added initial `set-resources` overrides for `alignment_summary` and `warm_msigdb_cache` (previously fell back to generic defaults)

### Fixed
- `dryrun`/`touch` exit codes — Now propagate Snakemake's real exit code instead of always reporting success, and no longer depend on always being invoked as `... && exit 0` to do so safely
- Stray user-site packages — `harold` wrapper and its Slurm job script now set `PYTHONNOUSERSITE=1` to isolate from `~/.local` pip `--user` packages
- Scratch temp dir crowding — Per-job scratch directories now nest under `/scratch/$USER/harold_temp/<uuid>` instead of `/scratch/$USER/<uuid>`
- Zero-read BAM outputs (#43) — Fixed bam_to_bigwig handling when BAM contains no reads
- Qualimap Java heap scaling (#42) — Now properly scales from job memory allocation
- kraken2 verbose output (#41) — Suppressed excessive per-read classification output to reduce log verbosity
- Temporary file staging — STAR sort outputs and split_bam outputs now properly staged in tempdir before moving
- Validation hardening — Improved input validation and Rivanna submission defaults
- Fastq validator escaping — Fixed bash variable escaping in FASTQ validation rule
- Strandedness normalization — Manifest strandedness values now consistently lowercase
- `pipeline.status.json` on Slurm runs — Fixed invalid JSON caused by an unescaped literal tab in `git_commit_tag`
- `unlock` silent failures — Now propagates the real exit code instead of always reporting success
- S3 transfer completeness — `s3_transfer_if_enabled` now depends on every pipeline output instead of a hand-picked subset, so it can no longer finish while other stages (DEG/GSEA, QC, etc.) are still running
- DEG/GSEA variant directory naming — Output directories now always include both the ERCC and batch tags (e.g. `wo_ercc_wo_batch`), not just when `use_ercc: both`
- Generated Slurm script corruption — Fixed a sed-substitution escaping bug that could corrupt the generated head-job script when `WORKDIR`, `GIT_COMMIT_TAG`, or similar values contained `/`, `&`, or `\`
- Removed a dead `CONDA_ACTIVATE` placeholder in the generated Slurm head-job template that had silently been a no-op since introduction
- `pipeline.*` state marker swap — Reordered marker creation/removal so there's never a brief window with no marker file present

## [1.2.1]

### Changed
- `harold --help` now prints the Singularity/Apptainer environment variables.

## [1.2.0]

### Changed
- The HAROLD wrapper now defaults `--sifdir` to `/project/dremel_lab/workflows/singularity_images`, prepares per-user caches under `/scratch/$USER/singularity`, honors standard `SINGULARITY_*` environment overrides, exports a dedicated scratch pull directory (`/scratch/$USER/singularity/images` when using the shared tree), and emits warnings when shared images are missing so users understand when a Docker pull to scratch will occur.
- `harold --runmode=init` now prints the cache directory (`--singcache`), the image directory (`--sifdir`), and the effective pull directory so users can confirm exactly where SIFs will be stored.
- Updated `docs/prereq.md` to spell out how the wrapper reports and uses the cache/tmp/pull directories versus the shared image directory, and to set expectations around the warning messages shown while new `.sif` files are staged.
- Documented where the composite `ref.fa`, `.gtf`, STAR index, and related files are written inside each work directory, added guidance for interpreting Snakemake’s verbose dry-run output, and expanded the usage guide with practical instructions for monitoring Slurm jobs and drilling into per-rule log files under `logs/`.

## [1.1.0]

### Added
- Optional diffex-normalized counts workflow, including per-sample RSeQC transcript quantification and generation of gene/transcript RPKM/TPM matrices.
- `config/rivanna/slurm-status.py` utility to surface job states and archive successful Slurm logs automatically.
- Quarto-based documentation site (`docs/`, `_quarto.yml`) that centralizes prerequisites, inputs/outputs, and run guidance for HAROLD.

### Changed
- Switched to the lab-hosted diffex and rseqc containers; exposed configuration knobs for diffex normalization (ERCC, batch, gene selection, host species).
- Improved Rivanna Apptainer usage by wiring scratch-based cache/tmp/image directories, exporting the runtime variables in both the wrapper and jobscript, introducing user-facing `--singcache` / `--sifdir` options, and setting `--account=dremel_lab` on Rivanna submissions.
- Updated the `harold` wrapper to submit the Snakemake head job through a generated `sbatch` script that carries the profile, module setup, and Apptainer prefix to the scheduler node.
- Tidied repository plumbing by aligning config/doc paths, extending `.gitignore`/`.codespell-ignore`, and tuning the Rivanna profile logging defaults.
- `harold --version` now prints a clean version string (no platform banner) thanks to a dedicated `-V/--version` flag in the wrapper.

### Fixed
- `diffex normalize` host selection now infers `Hs` vs `Mm` from both the diffex block and the top-level `host` option (e.g., mm39 maps to `--host Mm`).
- Hardened `rseqc_junction_annotation` to always create its junction file and log outputs cleanly, preventing spurious Snakemake failures.

## [1.0.0]

- Initial public release.
