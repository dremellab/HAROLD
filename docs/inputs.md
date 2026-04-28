# 📥 HAROLD Input Requirements

HAROLD accepts a small set of clearly defined inputs that ensure each run is reproducible, validated, and compatible with downstream analyses. This page describes all required and optional inputs and how HAROLD validates them before running the pipeline.

---

## 1. Sample Manifest (Required for Initialization)

The **sample manifest** (also called `samples.tsv` or `manifest.tsv`) is required only during the **initialization** phase (`runmode=init`). It defines the list of samples and their corresponding FASTQ file paths. The manifest must be a **tab-separated file** with the following columns:

| Column Name        | Description                                                                                                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sampleName`       | **Required.** Unique identifier for each sample. No duplicates allowed.                                                                                                                                      |
| `groupName`        | **Required.** Biological or experimental group label (e.g., `treated`, `control`, `infected`).                                                                                                              |
| `batch`            | **Optional.** Sequencing batch identifier for batch-effect correction. If used, **all samples must have a batch value** (no mixing of filled and empty values).                                               |
| `path_to_R1_fastq` | **Required.** Path to Read 1 FASTQ file (absolute or relative; must exist and be readable).                                                                                                                 |
| `path_to_R2_fastq` | **Required (PE) / Optional (SE).** Path to Read 2 FASTQ file. Leave empty for single-end libraries.                                                                                                        |
| `strandedness`     | **Required if `use_infer_strandedness=false`.** Library strandedness (`forward`, `reverse`, or `unstranded`). HAROLD always infers strandedness via RSeQC and reports it in output. The `use_infer_strandedness` config (default: true) controls whether the inferred values or manifest values are used for count extraction. When true, manifest values are ignored; when false, manifest values are required and used for extraction.       |

### Example Sample Manifest

```text
sampleName	groupName	batch	path_to_R1_fastq	path_to_R2_fastq	strandedness
S1	Control	B1	/data/fastq/S1_R1.fastq.gz	/data/fastq/S1_R2.fastq.gz	forward
S2	Treatment	B1	/data/fastq/S2_R1.fastq.gz	/data/fastq/S2_R2.fastq.gz	reverse
S3	Control	B2	/data/fastq/S3_R1.fastq.gz		unstranded
```

### Supported Library Types

HAROLD supports both **paired-end (PE)** and **single-end (SE)** sequencing data. FASTQ files must be **gzip-compressed** (`.fastq.gz`) and accessible from the file system at runtime. Both absolute and relative paths are supported; relative paths are resolved from the working directory.

### Validation Rules

Before execution, HAROLD validates the manifest automatically to prevent misconfiguration:

- **sampleName:** Must be unique across all samples.
- **groupName:** Must be non-empty for all samples.
- **Batch consistency:** If any sample has a batch value, **all samples must have one** (no mixing of filled and empty batch cells).
- **FASTQ files:** R1 file must exist and be readable for all samples. R2 file must be readable for PE samples (can be empty for SE).
- **Strandedness values:** Required and validated (must be `forward`, `reverse`, or `unstranded`) only when `use_infer_strandedness=false`. HAROLD always infers strandedness via RSeQC regardless of this setting.

If validation fails, HAROLD reports the specific error and stops before initialization.

---

## 2. Working Directory (`--workdir`)

The **working directory** is the central location where all output, logs, and configuration files are created. It must be specified for every HAROLD command and must be writable by the user.

During the **initialization** step (`runmode=init`), HAROLD creates the specified directory (if it does not already exist) and populates it with:

- A pipeline-specific configuration file (`config.yaml`).
- Template Snakemake rule files and subdirectories.
- A copy of the sample manifest for record keeping.
- Other required files for execution.

Once initialized, all subsequent commands (`dryrun`, `run`, etc.) must reference the same working directory.

---

## 3. Reference Configuration (Host, Additives, and Viruses)

The reference combination defines the biological context for alignment and quantification. These inputs are required **only for initialization (`runmode=init`)** and must correspond to one of HAROLD’s **supported reference components**.

### Parameters

- `--host`: Specifies the host genome to be used. Supported values are:

  - `hg38` for _Homo sapiens_
  - `mm39` for _Mus musculus_

- `--additives`: Defines optional spike-in sequences or synthetic controls. Supported values are:

  - `ERCC` for External RNA Control Consortium controls.
  - `BAC16Insert` for BAC16-derived KSHV genomic insert sequences.
  - Multiple additives can be supplied as a comma-separated list (e.g., `ERCC,BAC16Insert`).

- `--viruses`: Lists one or more viral genomes by their accession IDs. These must match one of the supported viral references in HAROLD’s library. Multiple accessions can be provided as a comma-separated list.

### Validation Rules

During initialization, HAROLD validates that:

- The selected host, additives, and viruses are recognized and supported.
- All required genome bundles are available for indexing.

If unsupported or misspelled identifiers are supplied, HAROLD will display an error message listing the allowed options.

---

## Summary

HAROLD requires minimal input to begin analysis: a correctly formatted sample manifest, a writable working directory, and valid reference selections for host, additives, and viruses. Together, these inputs ensure that HAROLD can dynamically build the appropriate reference index, validate experimental metadata, and execute reproducible, high-quality RNA-seq analyses across host and viral genomes.
