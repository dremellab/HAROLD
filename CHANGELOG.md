# Changelog

All notable changes to this project will be documented in this file.

## [dev]

- Added optional diffex-normalized counts workflow, including per-sample RSeQC transcript quantification and generation of gene/transcript RPKM/TPM matrices.
- Switched to the lab-hosted diffex and rseqc containers; exposed configuration knobs for diffex normalization (ERCC, batch, gene selection, host species).
- Improved Rivanna Apptainer usage by wiring scratch-based cache/tmp/image directories, exporting the runtime variables in both the wrapper and jobscript, and introducing user-facing `--singcache` / `--sifdir` options.
- Updated the `harold` wrapper to submit the Snakemake head job through a generated `sbatch` script that carries the profile, module setup, and Apptainer prefix to the scheduler node.
- Added `config/rivanna/slurm-status.py` utility to surface job states and archive successful Slurm logs automatically.

## [1.0.0]

- Initial public release.

