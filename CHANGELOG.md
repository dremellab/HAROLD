# Changelog

All notable changes to this project will be documented in this file.

## [dev]

### ⚠️ Breaking Changes
- **Config key renamed:** `infer_strandedness` → `use_infer_strandedness`. Update existing config files to use the new key name for clarity (true = use inferred values, false = use manifest values).

### Added
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

### Fixed
- Scratch temp dir crowding — Per-job scratch directories now nest under `/scratch/$USER/harold_temp/<uuid>` instead of `/scratch/$USER/<uuid>`
- Zero-read BAM outputs (#43) — Fixed bam_to_bigwig handling when BAM contains no reads
- Qualimap Java heap scaling (#42) — Now properly scales from job memory allocation
- kraken2 verbose output (#41) — Suppressed excessive per-read classification output to reduce log verbosity
- Temporary file staging — STAR sort outputs and split_bam outputs now properly staged in tempdir before moving
- Validation hardening — Improved input validation and Rivanna submission defaults
- Fastq validator escaping — Fixed bash variable escaping in FASTQ validation rule
- Strandedness normalization — Manifest strandedness values now consistently lowercase

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
