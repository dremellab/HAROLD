# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0]

### ⚠️ Breaking Changes
- **Config key renamed:** `infer_strandedness` → `use_infer_strandedness`. Update existing config files to use the new key name for clarity (true = use inferred values, false = use manifest values).
- **Shared `diffex` config block:** `use_ercc`, `ercc_mix`, `use_batch`, `batch_column`, and `genes_selection` moved out of `diffex_normalized_counts` and `diffex_deg_gsea` into one shared `diffex:` block, so the aggregate normalized-counts step and the per-contrast DEG/GSEA step can no longer disagree on ERCC/batch handling. The now-unused `diffex_normalized_counts.host` key was also removed (host was already sourced from the top-level `host:` config). As a result, `diffex_normalized_counts` output moved from `counts/normalized_counts/normalize.html` to `counts/normalized_counts/{variant}/normalize.html`, mirroring the DEG/GSEA variant layout, since `diffex.use_ercc`/`use_batch: both` now expands the aggregate step per-variant too. Update existing `config.yaml` files to the new schema (see #51).
- **New `rustqc` container required; `rseqc_tin_downsample_reads` config key removed:** existing `config.yaml` files need a `rustqc: "docker://seqinfomics/rustqc:0.2.1"` entry added to `containers:` (see the QC migration entries below). The now-unused `rseqc_tin_downsample_reads` key was removed — TIN no longer downsamples. Any cluster-profile `set-resources`/`set-threads` overrides keyed to `infer_strandedness`, `rseqc_read_distribution`, `downsample_bam_for_tin`, `rseqc_tin`, or `rseqc_junction_annotation` are now inert (those rules no longer exist) and can be deleted; the replacements are `rustqc_rna_combined_probe`, `rustqc_rna_combined`, `rustqc_rna_region`, and `mark_duplicates`.

### Added
- DEG and GSEA pipeline stage — New optional `diffex_deg_gsea` stage driven by a `contrasts.tsv` manifest (`harold --contrasts/-x`); runs DiffEx DEG (limma/DESeq2/edgeR) per contrast/variant/method followed by GSEA, with tri-state ERCC/batch variant expansion, a shared MSigDB cache warm-up, and `.rnk` sanitization for +/-Inf scores
- Pipeline run-state tracking — `harold` now writes `pipeline.{running,completed,failed,canceled}` markers and a `pipeline.status.json` sidecar to WORKDIR, updated on `runlocal`/`run` start, success, failure, and Slurm cancellation (SIGTERM/SIGINT trap)
- Live progress monitoring — Slurm head job now tails Snakemake's step-completion output and writes a human-readable progress summary into `pipeline.running`
- Structured CLI logging — `harold` output now uses leveled log helpers (`INFO`/`STEP`/`OK`/`WARN`/`ERROR`/`NEXT`) with next-step hints after `init`, `dryrun`, and job submission
- S3 deposit feature — Pipeline outputs can now be transferred to S3 buckets (GitHub #44)
- Alignment summary report — New QC report in the workflow
- FASTQ validation gating — Cutadapt can now be gated behind FASTQ validation
- Host-specific GTF support — Configuration now supports host-specific tRNA/chrR GTF files (removes repeats GTF wiring)
- **Migrated core QC tooling to `rustqc`:** `infer_strandedness` (RSeQC `infer_experiment.py`), `rseqc_read_distribution`, and `rseqc_junction_annotation` are now `rustqc` 0.2.1 modules instead — output formats confirmed byte-identical to RSeQC's own at the same legacy output paths, so downstream consumers (`aggregate_stranded_counts`, `junctions_to_bigbed`, `multiqc`) needed no changes. TIN also moved to `rustqc`, now at full read depth instead of RSeQC's downsampled workaround (see Changed below) ([dremellab/HAROLD#56](https://github.com/dremellab/HAROLD/issues/56)).
- **New duplicate-marking step + dupRadar/preseq/featureCounts QC outputs:** new `mark_duplicates` rule (Picard) feeds `rustqc`'s dupRadar (duplication rate vs. expression) and preseq (library complexity) modules — net-new QC capability HAROLD didn't have before, since no dup-marking step existed anywhere in the pipeline previously. featureCounts output (computed internally by dupRadar regardless of whether it's requested) is also tracked as a reference QC artifact under `{sample}/featurecounts/`; HAROLD's actual gene-level quantification is unchanged — still STAR `GeneCounts` via `aggregate_stranded_counts`.
- **`rustqc`'s RNA-seq-mode Qualimap report:** new `{sample}/qualimap_rnaseq/` output (5'→3' coverage bias, genomic origin classification, junction analysis) alongside the existing genomic (`bamqc`-mode) Qualimap report, which is untouched. `rustqc` only implements Qualimap's `rnaseq` mode, not `bamqc`, so this is an addition, not a replacement — asked upstream for `bamqc` mode support: [seqeralabs/RustQC#128](https://github.com/seqeralabs/RustQC/issues/128).
- **Additive/spike-in mapped reads in `alignment_summary.tsv`:** New `{additive}_mapped` column per configured additive (e.g. `ERCC_mapped`, `BAC16Insert_mapped`, `4SU1_mapped`), reporting primary BAM alignments to each additive/spike-in reference — mirrors the existing per-virus `{virus}_mapped` columns. Previously these reads were only visible folded into STAR's overall `reads_mapped_to_assembly` figure ([#52](https://github.com/dremellab/HAROLD/issues/52)).
- **`4SU1` additive documented:** `4SU1` (a synthetic spike-in control for 4-thiouridine metabolic-labeling RNA-seq, already usable via the generic additives mechanism) is now listed alongside `ERCC`/`BAC16Insert` in `harold --help`, `docs/prereq.md`, `docs/inputs.md`, `docs/usage.md`, `docs/outputs.md`, and `config/config.yaml` ([#53](https://github.com/dremellab/HAROLD/issues/53)).
- **Guard against submitting/unlocking into an already-running workdir:** `harold -m=run`/`runlocal`/`unlock` now refuse to proceed (and point at the file) if `${WORKDIR}/pipeline.running` already exists, since two runs racing on the same workdir/state (or unlocking a genuinely still-active run) can corrupt pipeline state. `dryrun` still runs normally against such a workdir (it's read-only), but now warns prominently at the end if a run may already be in progress, and skips the `Submit run with: harold -m=run` hint in that case ([#54](https://github.com/dremellab/HAROLD/issues/54)).
- **`pipeline.failed` now says which job(s) failed:** previously it only held the last progress snapshot. It (and the `pipeline.status.json` sidecar's new `num_failed_rules`/`failed_rules` fields) now include, per failed job: rule name, sample/wildcards, internal Snakemake jobid, external SLURM jobid, SLURM failure state (OOM/timeout/etc.), and the real per-job log path — parsed from Snakemake's own log, with jobs that ultimately succeeded on a later retry (`restart-times: 3`) correctly excluded ([#55](https://github.com/dremellab/HAROLD/issues/55)).
- **Fail fast on a single-level batch column:** when `diffex.use_batch` is `true`/`both`, HAROLD now validates at config-parse time (so `dryrun` catches it too) that `batch_column` has at least 2 distinct values — across all samples for `diffex_normalized_counts`, and among each contrast's `group1`/`group2` samples specifically for `diffex_deg_gsea`. Previously a single-level batch factor only surfaced deep inside the `diffex` container, after the DAG had already spent compute on everything upstream, as an opaque limma `contrasts can be applied only to factors with 2 or more levels` error.

### Changed
- **Legacy config migration guidance:** older run directories using the deprecated `infer_strandedness` flag or nested DiffEx option blocks should move to `use_infer_strandedness` and the shared top-level `diffex:` block before running on the current pipeline version.
- S3 namespace hierarchy — Updated `s3_transfer_harold.py` to include pipeline-name in S3 path hierarchy (`_HTS/HAROLD/sample_set/...`) for consistency with Chroma 2; added `s3_pipeline_name` config key (default: `HAROLD`)
- Repeats GTF configurability — Now a configurable reference, included in ref.gtf by default
- Default reference path — Updated fasta_gtf reference path to `/project/dremel_lab/workflows/reference_data/fasta_gtf`
- Manifest initialization — Strand values now normalized to lowercase during manifest parsing
- Documentation clarification — Improved strandedness documentation to clarify that HAROLD always infers strandedness and reports it; the config option controls only whether inferred or manifest values are used for count extraction
- S3 documentation accuracy — Corrected `s3_configuration.md`'s "Files Transferred to S3" table, which listed peak files, ataqv data, and tRNA/Tn5 outputs that HAROLD doesn't produce; documented the previously-missing SJ, DEG/GSEA, and normalized-counts transfers instead
- SLURM resource tuning — Added initial `set-resources` overrides for `alignment_summary` and `warm_msigdb_cache` (previously fell back to generic defaults)
- **TIN now runs at full read depth via `rustqc`, not RSeQC's downsampled `tin.py`:** benchmarked on a real combined host+virus BAM (`N_Mock_4h`, 689M reads, full hg38 GTF) at ~45min total for the whole `rustqc rna` module suite (TIN's own marginal cost, isolated via a `--skip-tin` diff, is ~12min of that) — vs. 7.5–13 hours per sample for RSeQC's `tin.py` on a 50M-read downsample in production, with repeated Slurm timeouts and resubmissions. The `downsample_bam_for_tin` rule this pipeline briefly had is gone entirely — no BAM downsampling happens before TIN anymore. TIN values will not match prior runs byte-for-byte — full depth vs. an ~8–12%-of-data downsample changes the input population by construction — so don't expect exact agreement diffing historical TIN output against post-migration runs. (Supersedes this same cycle's earlier "rseqc_tin runtime increased to 36 hours" change — `rseqc_tin` no longer exists.)
- **Final-state `pipeline.*` progress reporting:** `pipeline.completed` now reports the final step tally (`N / N steps complete (100%)`, `Remaining: 0 steps`) instead of being an empty marker file, matching the live format `pipeline.running` already used. `pipeline.failed` now preserves the last known progress snapshot instead of being emptied, so a failed run shows how far it got before failing. `runlocal` (previously untracked) now gets the same live progress monitoring as SLURM `run` jobs, via a tee'd Snakemake log.
- **`diffex` container bumped `0.5.2` → `0.5.5`:** picks up the DEG UpSetR crash fix (v0.5.3) and the GSEA `+Inf`/`-Inf` rank-clamp fix (v0.5.5, [dremellab/DiffEx#41](https://github.com/dremellab/DiffEx/pull/41)) that HAROLD's own `_sanitize_rnk.py` pre-processing step was working around. Switched to `docker://seqinfomics/diffex:0.5.5` (Docker Hub) rather than `ghcr.io/dremellab/diffex`, since no image newer than `0.5.2` has been published to GHCR ([dremellab/DiffEx#40](https://github.com/dremellab/DiffEx/issues/40)).

### Fixed
- **`counts_matrix.tsv` export no longer writes a hidden pandas index as a duplicate leading column:** gene labels are now exported as an explicit `gene` column before the metadata/sample-count fields, preventing the duplicated/offset look seen when the row index was left in place.
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
- **New `rustqc`/`mark_duplicates` rules now double their memory request on each retry:** `rustqc_rna_combined_probe` was observed OOM-killed in production (`MaxRSS` ~42GB against a 40GB request) — these rules had no real-scale memory data to size `set-resources` from. `mark_duplicates`, `rustqc_rna_combined_probe`, `rustqc_rna_combined`, and `rustqc_rna_region` now double their configured base `mem_mb` on each Snakemake retry (attempt 1 = base, 2 = 2x, 3 = 4x, 4 = 8x, via `restart-times: 3`) instead of failing identically on every attempt, via a new shared `_get_mem_mb()` helper (mirrors the existing `_get_threads()`/`_get_runtime()` pattern) ([dremellab/HAROLD#56](https://github.com/dremellab/HAROLD/issues/56)).
- **`rseqc_geneBody_coverage` no longer blocks `rule all`/`multiqc`/S3 transfer:** the rule reliably fails to complete for a majority of samples in practice (observed on a real 12-sample run: 8 samples never finished across a week of retries — TIMEOUT, CANCELLED, and FAILED attempts, 0-byte output). It was required by both `PIPELINE_TARGETS` and `multiqc`'s own input list, so those failures blocked the whole pipeline (`rule all` can never be satisfied) and the S3-transfer gate, which waits for everything else to finish first. It's no longer a required terminal target — still runnable standalone on demand — and `rustqc`'s new rnaseq-mode Qualimap coverage profile (see Added above) is a working interim gene-body-coverage-style signal in `multiqc` in the meantime ([dremellab/HAROLD#56](https://github.com/dremellab/HAROLD/issues/56)).
- **`fastq_validate_sample` OOM on large FASTQ files:** the rule had no memory override, so it used the pipeline-wide 40 GB default. `fastQValidator` runs unconditionally before `cutadapt` and blocks it on failure, so an OOM here (observed killed at ~40 GB validating a ~20-22 GB gzip R1/R2 pair) silently blocks the whole sample with no config workaround. Bumped to 120 GB (`config/rivanna/config.yaml`, matching the existing `cutadapt` allocation for the same files).
- **`cutadapt` no longer waits for every sample's FASTQ validation before trimming any sample:** it previously depended on a `fastq_validate_all` aggregate marker requiring all samples' `fastq_validate_sample` jobs to finish first, erasing per-sample parallelism from trimming onward and aborting the whole batch on one sample's bad FASTQ. It now depends only on that same sample's own `fastq_validate_sample` output; the now-unused `fastq_validate_all` rule was removed.
- **`alignment_summary.tsv` no longer silently drops samples missing an expected input:** previously, if any of a sample's four inputs (cutadapt report, fastQValidator report, STAR log, sorted BAM) was missing, `_alignment_summary.py` skipped that sample entirely with no row and no warning — indistinguishable from the sample never having been part of the run. Every sample directory now gets a row, with `NA` in whichever columns can't be computed from the missing file(s), plus a stderr warning (captured in `alignmentqc/alignment_summary.log`) naming exactly what was missing.

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
