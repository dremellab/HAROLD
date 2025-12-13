# 📥 HAROLD Input Requirements

HAROLD accepts a small set of clearly defined inputs that ensure each run is reproducible, validated, and compatible with downstream analyses. This page describes all required and optional inputs and how HAROLD validates them before running the pipeline.

---

## 1. Sample Manifest (Required for Initialization)

The **sample manifest** (also called `samples.tsv` or `manifest.tsv`) is required only during the **initialization** phase (`runmode=init`). It defines the list of samples and their corresponding FASTQ file paths. The manifest must be a **tab-separated file** with the following columns:

| Column Name        | Description                                                                                                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sampleName`       | A unique identifier for each sample. No duplicates are allowed.                                                                                                                                              |
| `groupName`        | A label representing the biological or experimental group (for example, `treated`, `control`, `infected`).                                                                                                   |
| `batch`            | An optional batch identifier if the experiment spans multiple sequencing batches. This helps downstream normalization and batch correction.                                                                  |
| `path_to_R1_fastq` | The absolute or relative path to the FASTQ file containing **Read 1** sequences.                                                                                                                             |
| `path_to_R2_fastq` | The path to the **Read 2** FASTQ file for paired-end libraries. For single-end libraries, this column can be left blank or omitted.                                                                          |
| `strandedness`     | (Optional) Library strandedness. Valid values include `forward`, `reverse`, or `unstranded`. If this field is missing or left empty, HAROLD will automatically infer strandedness using **RSeQC** utilities. |

### Example Sample Manifest

```text
sampleName	groupName	batch	path_to_R1_fastq	path_to_R2_fastq	strandedness
S1	Control	B1	/data/fastq/S1_R1.fastq.gz	/data/fastq/S1_R2.fastq.gz	forward
S2	Treatment	B1	/data/fastq/S2_R1.fastq.gz	/data/fastq/S2_R2.fastq.gz	reverse
S3	Control	B2	/data/fastq/S3_R1.fastq.gz		unstranded
```

### Supported Library Types

HAROLD supports both **paired-end (PE)** and **single-end (SE)** sequencing data. FASTQ files must be **gzip-compressed** (`.fastq.gz`) and accessible from the file system at runtime. Absolute paths are required.

### Validation Rules

Before execution, HAROLD validates the manifest automatically to prevent misconfiguration. The validation checks include:

- Each `sampleName` must be unique.
- FASTQ files referenced in `path_to_R1_fastq` (SE,PE) and `path_to_R2_fastq` (PE) must exist and be readable.
- Column names must match the expected header structure.
- The strandedness field, if provided, must be one of the accepted values. (forward/reverse/unstranded)
- Group and batch assignments are checked for consistency to avoid missing metadata.

If any issue is detected, HAROLD will stop execution and report the specific error message to guide correction before rerunning initialization.

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
