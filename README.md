# HAROLD

**HAROLD** (**H**igh-throughput **A**lignment and **R**NA **O**utput **L**evel **D**etection) is a reproducible **RNA-seq quantification and normalization pipeline** built with Snakemake, for host + optional-virus co-analysis: it aligns reads with STAR against a composite reference (a host genome, optional additives like `ERCC`, and one or more viral genomes), runs a full QC suite (Cutadapt, Kraken2, Qualimap/RustQC, MultiQC), and quantifies gene-level counts.

The pipeline optionally runs DiffEx-based differential expression (DESeq2/edgeR/limma) and GSEA per contrast, with tri-state ERCC-spike-in and batch-correction variants, and produces normalized-counts matrices for downstream analysis. It is driven end-to-end by the `harold` wrapper script for SLURM/HPC execution on Rivanna, with optional S3 archival of final outputs.

📖 **[Read the full documentation](https://dremellab.github.io/HAROLD/dev/docs/index.html)** for prerequisites, usage, pipeline architecture, inputs/outputs, and more.

[Architecture diagram (Lucidchart)](https://lucid.app/lucidspark/f9392d93-74f5-4854-9a02-dae8c7653a56/edit?viewport_loc=-1232%2C-914%2C2520%2C2121%2C3B0CRSot8otI&invitationId=inv_11ca1fed-2487-4d4e-b15b-c8122c887398)
