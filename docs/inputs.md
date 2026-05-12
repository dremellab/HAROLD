# 📥 HAROLD Input Requirements

HAROLD accepts a small set of clearly defined inputs that ensure each run is reproducible, validated, and compatible with downstream analyses. This page describes all required and optional inputs and how HAROLD validates them before running the pipeline.

---

## ⚠️ Breaking Changes (v1.3.0+)

### Config Key Renamed: `infer_strandedness` → `use_infer_strandedness`

**If upgrading from v1.2.x:** Update your `config.yaml` file.

| Old Key | New Key | Behavior |
|---|---|---|
| `infer_strandedness` | `use_infer_strandedness` | Controls whether to use RSeQC-inferred strandedness (`true`, default) or manifest values (`false`) for count extraction. |

**Important:** HAROLD **always infers and reports** strandedness via RSeQC regardless of this setting. The config key only controls which strand assignment is **used for quantification**:
- **`use_infer_strandedness: true`** (default) — Manifest `strandedness` column ignored; RSeQC inference is authoritative.
- **`use_infer_strandedness: false`** — Manifest `strandedness` column required and used; overrides RSeQC inference.

**Migration:** If you have existing `config.yaml` files with `infer_strandedness`, rename the key. The behavior remains the same; this is purely a naming clarification.

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
- **Strandedness values:** Required and validated (must be `forward`, `reverse`, or `unstranded`, case-insensitive) only when `use_infer_strandedness=false`. Values are normalized to lowercase internally (Forward → forward, REVERSE → reverse, etc.). HAROLD always infers strandedness via RSeQC regardless of this setting.

If validation fails, HAROLD reports the specific error and stops before initialization.

#### Strandedness Inference vs. Manifest Values

HAROLD employs a **two-step strandedness strategy**:

1. **Inference (always happens):** RSeQC `infer_experiment.py` analyzes read pair orientation and reports a stranded result (forward, reverse, or unstranded based on confidence threshold). This inference is output in `results/{sample}/rseqc/{sample}.strandedness.txt` and aggregated in `results/counts/sample_strandedness.tsv`.

2. **Selection (config-driven):** The `use_infer_strandedness` config key selects which strandedness is **used for count extraction**:
   - **true (default):** Use inferred strandedness; manifest column ignored.
   - **false:** Use manifest column; inferred strandedness reported but not used for counts.

**Recommendation:** Leave `use_infer_strandedness: true` unless you have a strong reason to override (e.g., known library prep protocol contradicts inference). Inferred values are more robust than manual annotation.

---

## 2. Working Directory (`--workdir`) {#working-directory}

The **working directory** is the central location where all output, logs, and configuration files are created. It must be specified for every HAROLD command and must be writable by the user.

During the **initialization** step (`runmode=init`), HAROLD creates the specified directory (if it does not already exist) and populates it with:

- A pipeline-specific configuration file (`config.yaml`).
- Template Snakemake rule files and subdirectories.
- A copy of the sample manifest for record keeping.
- Other required files for execution.

Once initialized, all subsequent commands (`dryrun`, `run`, etc.) must reference the same working directory.

---

## 3. Reference Configuration (Host, Additives, and Viruses) {#reference-configuration}

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

### Reference Data Paths

HAROLD sources reference sequences and annotations from a centralized repository. Default paths are:

| Type | Default Location |
|---|---|
| **Host/viral FASTA & GTF** | `/project/dremel_lab/workflows/reference_data/fasta_gtf/` |
| **Singularity container images** | `/project/dremel_lab/workflows/singularity_images/` |

To use custom reference paths, edit the `config.yaml` key:
```yaml
fastas_gtfs_dir: "/path/to/custom/references"
```

Available reference files in the default location include FASTA and GTF for:
- Host genomes: `hg38`, `mm39` (with comprehensive gene annotations)
- Viral references: All supported accessions (KSHV, SARS-CoV-2, HSV-1, etc.)
- Additives: ERCC control sequences, BAC16Insert

---

### Host-Specific GTF Files (tRNA and Repeats)

By default, HAROLD includes **host genome gene annotations** (protein-coding, lncRNA, etc.) from NCBI. You can optionally augment the reference with **specialized annotation files**:

#### `trnas_gtf` — tRNA Gene Annotations

**Purpose:** Include transfer RNA (tRNA) genes in quantification with explicit coordinates.

**Configuration:**
```yaml
trnas_gtf:
  hg38: "/project/dremel_lab/workflows/reference_data/fasta_gtf/hg38.tRNAs.hg38chroms.gtf"
  mm39: "/project/dremel_lab/workflows/reference_data/fasta_gtf/mm39.tRNAs.mm39chroms.gtf"
```

**When to use:**
- If your experiment has tRNA-focused analysis (e.g., tRNA quantification, tRNA fragment analysis)
- tRNA GTF is separate because genomic tRNA databases (tRNAscan-SE, GtRNAdb) differ from NCBI standard annotations
- Leave empty or commented if tRNA quantification not needed

**Expected format:** GTF file with `gene_type = tRNA` entries, chromosome IDs matching host genome (chr1–chrY, not scaffolds).

---

#### `chrr_gtf` — Repeats and Ribosomal RNA Annotations

**Purpose:** Include genomic repeats and ribosomal RNA (rRNA) regions in the reference annotation.

**Configuration:**
```yaml
chrr_gtf:
  hg38: "/path/to/hg38.repeats.gtf"
  mm39: "/path/to/mm39.repeats.gtf"
```

**When to use:**
- If you want to explicitly quantify rRNA contamination or repeat-associated reads
- Repeats GTF is now **included in the default `ref.gtf` by default** (no longer requires chrR flag)
- Useful for multi-genome pipelines where repeat masking is important (e.g., viral integration site analysis)

**Expected format:** GTF file with repeat annotations (RepBase, rmsk annotations), chromosome IDs matching host genome. Can include rRNA genes, satellite DNA, SINEs, LINEs, etc.

**Note:** Set to empty string or omit if repeat quantification not needed; reference will be built without repeat annotations.

---

### Validation Rules

During initialization, HAROLD validates that:

- The selected host, additives, and viruses are recognized and supported.
- All required genome bundles are available for indexing.
- (If provided) Custom GTF files exist and are readable.

If unsupported or misspelled identifiers are supplied, HAROLD will display an error message listing the allowed options.

---

## 4. Optional: Input Validation and Quality Gating

HAROLD can optionally validate input FASTQ files before alignment to detect contamination or formatting issues.

### FASTQ Validation Gating

**Configuration:**
```yaml
validate_fastq: true  # default: false
```

**When enabled:**
1. FastQValidator analyzes each input FASTQ file (R1 and R2) for format compliance
2. Reports total sequences, line count, and any formatting errors
3. Cutadapt proceeds regardless of validation results (non-blocking)

**Validation checks include:**
- Correct FASTQ format (4-line records with @, sequence, +, qualities)
- Sequence length consistency
- Quality score range validity (Phred 0–93)
- Invalid characters in sequence or quality strings

**Output:** Validation report in `results/{sample}/fastq_validation/{sample}.fastq_validator.txt` (included in alignment summary if validation is enabled)

**Use case:** Enable for new or untrusted sample sources to catch obvious formatting or contamination issues early. Validation adds minimal runtime overhead (< 1 min per sample).

**Red flags from validation output:**
- Mismatched R1/R2 sequence counts (indicates paired-end mismatch or corruption)
- Non-standard quality scores (e.g., raw ASCII instead of Phred+33)
- High % low-quality bases (> 50% Q < 20) suggests failed sequencing run

---

## Summary

### Required Inputs

1. **Sample manifest** (TSV) — sample names, group labels, FASTQ file paths
2. **Working directory** — output and configuration location (created if doesn't exist)
3. **Reference selection** — host (hg38 or mm39) + viral accessions (comma-separated)

### Optional but Recommended Inputs

4. **Strandedness specification** (in manifest or config) — only needed if `use_infer_strandedness: false`
5. **Custom GTF files** (in config) — tRNA and repeat annotations if desired
6. **FASTQ validation** (in config) — enable for quality screening of input files

Together, these inputs ensure that HAROLD can dynamically build the appropriate reference index, validate experimental metadata, and execute reproducible, high-quality RNA-seq analyses across host and viral genomes. Most users need only the three required inputs; optional inputs add specialized functionality for specific experimental designs (tRNA analysis, repeat quantification, quality gating).
