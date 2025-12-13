# 🧬 HAROLD — RNA-seq Quantification Pipeline

**HAROLD** (High-throughput Alignment and RNA Output Level Detection) is a modular and reproducible **RNA-seq quantification pipeline**, designed for seamless integration with downstream analysis tools such as [**DiffEx**](https://github.com/dremellab/DiffEx).

HAROLD automates the process from raw FASTQ files to normalized count matrices and interactive reports that use MultiQC for visualization and quality control summaries; these outputs can then be parsed by the DiffEx package to generate additional Quarto-based interactive reports for differential gene expression and gene set enrichment analysis, making it ideal for **virus-host transcriptomic studies** and **multi-genome RNA-seq** experiments.

---

## 🚀 Key Features

- **HAROLD supports custom reference generation.** It allows users to build composite STAR references that include a host genome such as `hg38` (human) or `mm39` (mouse), optional additives like `ERCC` or `BAC16Insert` (or both), and one or more viral genomes from a curated collection.

- **HAROLD includes a comprehensive viral reference library.** The current library is summarized in the following table:

| Accession     | Virus Name                                                                        | Description                                            |
| ------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------ |
| NC_007605.1   | Epstein–Barr virus                                                                | Human gammaherpesvirus 4                               |
| NC_006273.2   | Cytomegalovirus                                                                   | Human betaherpesvirus 5                                |
| NC_001664.4   | HHV‑6A                                                                            | Human betaherpesvirus 6A                               |
| NC_000898.1   | HHV‑6B                                                                            | Human betaherpesvirus 6B                               |
| NC_001716.2   | HHV‑7                                                                             | Human betaherpesvirus 7                                |
| NC_009333.1   | KSHV                                                                              | Human gammaherpesvirus 8                               |
| NC_045512.2   | SARS‑CoV‑2                                                                        | Severe acute respiratory syndrome coronavirus 2        |
| MN485971.1    | HIV                                                                               | Human immunodeficiency virus (Belgium isolate)         |
| NC_001806.2   | HSV‑1 strain 17                                                                   | Human alphaherpesvirus 1 (Herpes simplex virus type 1) |
| KT899744.1    | HSV‑1 strain KOS                                                                  | Human alphaherpesvirus 1 (HSV‑1) strain KOS            |
| KT899744delRR | HSV‑1 strain KOS‑deleted terminal repeats Δ1‑9603, Δ125845‑126977, Δ145361‑151974 | Custom HSV‑1 strain with deleted terminal repeats      |
| MH636806.1    | MHV68                                                                             | Murine herpesvirus 68, strain WUMS                     |

- **HAROLD dynamically generates the required reference bundles.** It builds STAR indices on the fly using selected host and viral genomes, removing the need for large prebuilt references and reducing storage overhead.

- **HAROLD is powered by Snakemake for workflow orchestration.** Each stage, from index creation to alignment and normalization, is managed through clearly defined rules that ensure reproducibility and modular execution.

- **HAROLD provides flexible alignment and quantification.** It performs both gene- and transcript-level counting, using STAR for alignment and feature-based quantification tools for accurate expression measurement.

- **HAROLD performs normalization with trusted statistical frameworks.** It calculates FPKM, TPM, and other normalization metrics using **limma**, **edgeR**, and **DESeq2**, leveraging the **DiffEx** package for visualization and interactive exploration.

- **HAROLD includes seamless HPC integration.** The pipeline can be run on clusters like Rivanna through a single wrapper script that supports initialization, dry-run validation, and SLURM-based execution for efficient job scheduling.

- **HAROLD produces a comprehensive MultiQC report.** This report aggregates extensive quality-control metrics, incorporating results from FastQC, FastQ Screen, RSeQC tools such as tin.py, and other QC modules that evaluate read quality, mapping bias, coverage uniformity, and gene body integrity. The MultiQC report provides an interactive dashboard where users can assess sample-level performance and experiment-wide consistency.

- **HAROLD is designed for direct downstream compatibility.** The pipeline produces raw count matrices and an input sample manifest that are ready for import into **DiffEx** or other RNA-seq analysis frameworks.

- **HAROLD can autodetect strandedness.** Users can specify strandedness directly in the sample manifest if it is known, or let HAROLD infer it automatically using RSeQC utilities, ensuring accurate quantification across diverse library preparation protocols.

---

## 🧬 Workflow Overview

HAROLD orchestrates the full RNA-seq analysis pipeline in a reproducible manner, capturing the central philosophy of transcriptomic studies. A typical RNA-seq experiment begins with sequencing reads that represent fragments of expressed genes. These reads provide a snapshot of which genes are active and at what levels across different samples or experimental conditions. HAROLD automates this process by first assembling a composite reference based on user-selected host, viral, and additive components. This ensures that both host and pathogen contributions to transcriptional changes can be examined in a single coherent analysis framework.

Reads are trimmed using Cutadapt to remove adapters and low-quality regions before alignment. The pipeline then builds a STAR index for the selected reference and performs highly efficient alignments that preserve splicing information critical for downstream interpretation. Once aligned, HAROLD generates both gene- and transcript-level quantifications, converting raw read counts into normalized measures such as FPKM and TPM. These values help compare expression levels between samples by adjusting for gene length and sequencing depth, allowing researchers to identify genes that change meaningfully rather than artifacts of sampling.

Beyond quantification, HAROLD emphasizes transparency and interpretability. Quality-control summaries and interactive MultiQC reports consolidate information from multiple tools, offering insights into sequencing quality, alignment efficiency, and potential biases. The final deliverables include BAM and BAI files for visualization, along with bigWig coverage and junction bigBed tracks, which together create a complete resource for exploring transcriptional landscapes, detecting novel features, and setting the stage for differential expression analysis in DiffEx or other frameworks.

---
