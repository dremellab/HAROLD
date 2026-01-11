# Changelog

All notable changes to this project will be documented in this file.

## [dev]

### Changed
- The HAROLD wrapper now defaults `--sifdir` to `/project/dremel_lab/workflows/singularity_images`, prepares per-user caches under `/scratch/$USER/singularity`, honors standard `SINGULARITY_*` environment overrides, and emits warnings when shared images are missing so users understand when a Docker pull to scratch will occur.
- `harold --runmode=init` now prints both the cache directory (`--singcache`) and the image directory (`--sifdir`) so users can confirm each path independently during initialization.

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
