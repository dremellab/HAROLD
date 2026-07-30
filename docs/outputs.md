# 📊 HAROLD Output Files

HAROLD produces a comprehensive set of outputs organized into clearly structured directories within your working directory. This page describes all output types, their locations, file formats, and how to interpret them.

---

## Output Directory Structure

After a successful run, your HAROLD working directory will contain:

```
workdir/
├── ref/                              # Reference files created during initialization
│   ├── ref.fa                        # Combined host + additives + viral FASTA
│   ├── ref.fa.fai                    # FASTA index
│   ├── ref.gtf                       # Concatenated GTF annotation
│   ├── ref.fixed.gtf                 # Cleaned GTF for Snakemake/rustqc
│   ├── ref.genes.bed12               # Gene regions in BED12 format (RSeQC's geneBody_coverage/read_GC only)
│   ├── ref.genes.genepred            # GenePred format annotation
│   ├── ref.genes.genepred_w_geneid   # GenePred with gene IDs
│   ├── STAR_no_GTF/                  # STAR genome index directory
│   ├── ref.fa.regions                # Genome regions metadata
│   ├── ref.fa.regions.host           # Host genome regions
│   └── ref.fa.regions.viruses        # Viral genome regions
│
├── results/
│   ├── {sample}/
│   │   ├── trim/                     # Adapter-trimmed FASTQ files
│   │   ├── STAR/                     # Alignment BAM files and metrics
│   │   ├── bigwigs/                  # Normalized coverage tracks
│   │   ├── qualimap/                 # Genomic BAM QC report (Qualimap bamqc)
│   │   ├── qualimap_rnaseq/          # RNA-seq-specific QC report (rustqc's Qualimap rnaseq module)
│   │   ├── rseqc/                    # RNA-seq QC metrics (strandedness/read_distribution/TIN/junction via
│   │   │                             #   rustqc; geneBodyCoverage/GC.xls still via RSeQC directly, see below)
│   │   ├── dupradar/                 # Duplication rate vs. expression (rustqc's dupRadar module)
│   │   ├── preseq/                   # Library complexity estimate (rustqc's preseq module)
│   │   ├── featurecounts/            # Gene/biotype counts (rustqc's featureCounts module -- QC
│   │   │                             #   reference only, NOT the pipeline's quantification source)
│   │   ├── kraken2/                  # Pathogen detection reports
│   │   ├── counts/                   # Per-sample count matrices
│   │   └── fastq_validation/         # FASTQ validation logs (always produced, blocks Cutadapt on failure)
│   │
│   ├── counts/                       # Aggregate count matrices
│   ├── alignmentqc/                  # Alignment summary statistics
│   ├── multiqc_report.html           # Interactive QC dashboard
│   └── multiqc_data/                 # MultiQC data tables
│
├── samples.tsv                       # Copy of input sample manifest
├── config.yaml                       # Pipeline configuration file
├── .snakemake/                       # Snakemake metadata
└── logs/                             # Rule-specific SLURM job logs
```

---

## Reference Files

Created during the first Snakemake run and reused across all subsequent runs in the same work directory.

| File | Description |
|------|---|
| `ref/ref.fa` | **Combined reference FASTA** containing host genome, additives (ERCC, BAC16Insert, 4SU1), and all selected viral sequences. Single source of truth for all alignments. |
| `ref/ref.gtf` | **Concatenated GTF** with annotations from host, viruses, and optional tRNA/repeats GTF files. |
| `ref/ref.fixed.gtf` | **Cleaned GTF** with normalized formatting for Snakemake compatibility. |
| `ref/ref.genes.bed12` | **BED12 format gene annotations** derived from GTF. Used by the RSeQC tools that still run directly (`geneBody_coverage.py`, `read_GC.py`) — `rustqc`'s modules (read distribution, TIN, junction detection) read the GTF directly instead. |
| `ref/ref.genes.genepred` / `.genepred_w_geneid` | **GenePred format** used by RSeQC for transcript quantification (FPKM/TPM calculation). |
| `ref/ref.fa.regions*` | **Metadata files** tracking which genomic regions belong to host vs. viruses. Used internally for splitting alignments. |
| `ref/STAR_no_GTF/` | **STAR genome index** directory with all pre-built index files (SA, SAindex, chrLength.txt, etc.). Index is created once and reused for all samples. |

---

## Per-Sample Output Files

Each sample produces the following files under `results/{sample}/`:

### Trimmed Reads

| File | Description |
|------|---|
| `trim/{sample}.R1.trim.fastq.gz` | **Read 1 FASTQ** after adapter removal by Cutadapt. Quality-filtered and trimmed. |
| `trim/{sample}.R2.trim.fastq.gz` | **Read 2 FASTQ** (paired-end only) after trimming. |
| `trim/{sample}.cutadapt.report.txt` | **Cutadapt statistics** report showing bases trimmed, reads discarded, and adapter detection rates. |

### Alignment Files

#### `STAR/{sample}.Aligned.sortedByCoord.out.bam`

**Format:** BAM (binary SAM) file, coordinate-sorted
**Index:** `.bai` file (must exist for IGV/Samtools random access)

| Header (@SQ) | Description |
|---|---|
| SN (sequence name) | Chromosome/contig ID from reference FASTA (e.g., chr1, NC_009333.1:1-137895). |
| LN (sequence length) | Length in bp. |

| Alignment Field | Standard BAM Semantics | HAROLD Usage |
|---|---|---|
| QNAME | Read name. | As-is from FASTQ. |
| FLAG | Bitwise flags (unmapped, secondary, supplementary, etc.). | Secondary (256) and supplementary (2048) alignments **excluded** from count matrices; only primary alignments (FLAG ≤ 127) counted. |
| RNAME | Reference sequence (chromosome). | Genomic contig from header. |
| POS | 1-based leftmost mapping position. | Genomic coordinate. |
| MAPQ | Mapping quality. STAR uses: 255 = uniquely mapped, < 255 = multi-mapped (not in counts). | Only MAPQ=255 reads used for quantification. |
| CIGAR | Alignment operations (M, I, D, N, S, H). | Used by `rustqc`, RSeQC, bedtools for exon overlap. |
| RNEXT, PNEXT | Mate reference and position (paired-end only). | Standard BAM. |
| TLEN | Template length (inferred insert size, paired-end only). | Used for strand inference validation. |
| SEQ | Read sequence. | Standard BAM. |
| QUAL | Base qualities (Phred-scaled). | Standard BAM. |
| Optional tags | AS:i (alignment score), NM:i (edit distance), jM/jI (intron coords), etc. | STAR-specific tags for advanced filtering. |

**Key filtering in HAROLD:** Reads with MAPQ < 255 OR FLAG ≥ 256 (secondary/supplementary) are silently excluded from all downstream analyses (counting, visualization, etc.). Use `samtools view -F 256 -F 2048` to count unique primary alignments.

---

#### `STAR/{sample}.Aligned.sortedByCoord.out.bam.bai`

**Format:** BAM index (binary, BAI format)
**Purpose:** Random-access index for fast `samtools view -b chr1:100-1000` queries in BAM file. Auto-generated by STAR.
**Required for:** IGV, Samtools, bedtools operations on large BAM files.

---

#### `STAR/{sample}.Aligned.toTranscriptome.out.bam` (Optional)

**Format:** BAM, transcript-coordinate sorted
**Condition:** Only created if `star_save_transcript_sam: true` in config.yaml (default: false).
**Contents:** Same reads as coordinate-sorted BAM, but aligned to transcript coordinates (position within transcript, not genomic position). Useful for quantification tools like Kallisto/Salmon, RSEM. Not used by HAROLD.

---

#### `STAR/{sample}.ReadsPerGene.out.tab`

**Format:** Tab-separated text file (no header)
**Rows:** One per gene/feature from GTF + metadata rows

| Column | Data Type | Description |
|---|---|---|
| 1 | String | **Gene ID** (from GTF gene_id). First few rows are metadata: `N_unmapped`, `N_multimapping`, `N_noFeature`, `N_ambiguous`. |
| 2 | Integer | **Count (unstranded)**: All reads overlapping this gene (regardless of strand). |
| 3 | Integer | **Count (forward strand)**: Reads on forward strand only. |
| 4 | Integer | **Count (reverse strand)**: Reads on reverse strand only. |

**Example:**
```
N_unmapped	100000	NA	NA
N_multimapping	50000	NA	NA
ENSG00000000003	1000	400	600
ENSG00000000005	500	100	400
```

**HAROLD usage:** Rows starting with `N_` are discarded. Columns 3–4 are selected by strandedness (forward-strand = use column 3, reverse-strand = use column 4, unstranded = use column 2). Result is the input to count matrix aggregation.

---

#### `STAR/{sample}.SJ.out.tab`

**Format:** Tab-separated text file
**Rows:** One row per detected splice junction (exon-exon boundary)

| Column | Data Type | Description |
|---|---|---|
| 1 | String | Chromosome/contig. |
| 2 | Integer | Intron start (1-based, position of last base of upstream exon). |
| 3 | Integer | Intron end (1-based, position of first base of downstream exon). |
| 4 | String | Intron strand (`+` or `-`). |
| 5 | Integer | Intron motif (1=GT/AG canonical, 2=CT/AC, 3=GC/AG, 4=AT/AC, 0=non-canonical). |
| 6 | Integer | Annotated in GTF? (0=no, 1=yes). |
| 7 | Integer | Unique read count supporting junction (reads with MAPQ > 0). |
| 8 | Integer | Multi-mapped read count (MAPQ = 0). |

**Use case:** QC check for unannotated junctions (potential artifact, virus, or novel isoform). High count of non-canonical (motif=0) junctions suggests contamination or technical error.

---

#### `STAR/{sample}.Log.final.out`

**Format:** Key-value text file (used by alignment_summary.py script)

| Key | Sample Value | Description |
|---|---|---|
| Number of input reads | 50000000 | Total reads after trimming (from Cutadapt). |
| Uniquely mapped reads number | 48000000 | Primary alignments (MAPQ=255). |
| Number of reads mapped to multiple loci | 1200000 | Multi-mapped reads (excluded from counts). |
| Number of reads mapped to too many loci | 300000 | Reads mapping to > 250 loci (excluded). |
| Number of reads unmapped: too many mismatches | 200000 | Quality filter. |
| Number of reads unmapped: too short | 150000 | Min length filter. |
| Uniquely mapped reads % | 96.00 | (uniquely_mapped / input) × 100. |
| Average mapped length | 150.5 | Mean insert size (PE) or read length (SE). |

**Use case:** Quickly parse mapping metrics without re-scanning BAM: `grep "Uniquely mapped" {sample}.Log.final.out`.

---

#### `STAR/{sample}.{regionname}.bam` (Split BAMs)

**Format:** BAM, coordinate-sorted, subset of main BAM

**Contents:** Reads with **primary alignment** to chromosomes/contigs for this region only.

- `{sample}.hg38.bam` = only reads aligning to host chr1–chrY (or chrM, etc. for selected host)
- `{sample}.NC_009333.1.bam` = only reads aligning to KSHV genome
- etc. for all hosts, additives, and viruses

**Creation:** After primary BAM generation, reads are split by `samtools view` using reference regions from `ref.fa.regions.{host,viruses}` files.

**Use case:** Downstream tools that require single-reference BAMs (e.g., MACS2 peak calling per-virus, ataqv per-region).

### Normalization and Coverage Tracks: BigWig Files

#### `bigwigs/{sample}.{regionname}.bw`

**Format:** BigWig (binary, indexed), compressed WIG format
**Source:** Generated from split BAM files via `bedtools genomecov` + `wigToBigWig` conversion
**Signal values:** RPM-normalized (reads per million)

| Property | Description |
|---|---|
| Data type | Float (read depth per genomic position) |
| Normalization | RPM = (read count at position / total_aligned_reads_in_region) × 1e6 |
| Coverage | Positive strand shown as positive, negative strand as negative (signed strand info). |
| Resolution | Per-base (1 bp precision) for regions with reads; sparse for zero-coverage regions. |

**Example regions in filename:**

- `{sample}.hg38.bw` = host genome coverage (non-viral reads)
- `{sample}.NC_009333.1.bw` = KSHV-specific coverage (reads aligning only to KSHV)
- `{sample}.ERCC.bw` = ERCC spike-in coverage (if ERCC added to reference)

**Use case:** Load all `.bw` files for a sample into IGV alongside the primary BAM for integrated visualization. Useful for spotting coverage biases, unimodal peaks (POI), GC-correlated coverage dropouts.

**Interpretation:** Peak height (RPM units) directly comparable within region but NOT across regions (each region normalized independently by its own total reads). For cross-region comparisons, normalize BigWigs by region-specific mapping statistics.

### Quality Control

#### Qualimap (Genomic BAM QC): `qualimap/qualimapReport.html`

**Format:** Self-contained HTML with embedded JavaScript and CSS
**Tool:** Qualimap `bamqc` module (unchanged by the `rustqc` migration below)
**Contents:** Interactive QC dashboard

| Tab / Metric | Description |
|---|---|
| **Coverage Profile** | Distribution of read depths (median, Q1/Q3 per contig). Red flag: bimodal/skewed distributions suggest coverage dropout, SVs, or amplification bias. |
| **GC Content Bias** | X: GC%, Y: read count. Ideal: flat line. Red flag: V-shaped curve indicates uncorrected GC bias (Illumina-specific). |
| **Mismatches** | Error rate per read position. Ideal: ≤ 2%. Red flag: 3' end elevation suggests quality issues in later sequencing cycles. |
| **Chromosome Stats** | Per-contig mean coverage, stdev, % mapped. Use for sex-chr imbalance detection (XX vs. XY), mitochondrial enrichment checks. |
| **Insert Size** (PE) | Distribution of fragment lengths (TLEN field). Mode reflects library prep protocol (typically 200–800 bp WGS, 100–400 bp low-input). Red flag: multimodal or extreme outliers → contamination/artifacts. |

---

#### Qualimap (RNA-seq QC): `qualimap_rnaseq/qualimapReport.html`

**Format:** Self-contained HTML with embedded JavaScript and CSS, plus `rnaseq_qc_results.txt` (plain text) and coverage-profile TSVs/plots under `raw_data_qualimapReport/`/`images_qualimapReport/`
**Tool:** Qualimap `rnaseq` module, reimplemented by `rustqc` — a separate, additional report from the genomic `bamqc` one above, not a replacement for it. `rustqc` only implements Qualimap's `rnaseq` mode (there's no `report.pdf` here, unlike the `bamqc` report).
**Contents:** RNA-seq-specific QC — this is where gene-body 5'→3' coverage bias lives, since HAROLD's RSeQC-based `geneBody_coverage.py` (below) is not guaranteed to run

| Metric | Description |
|---|---|
| **Reads Genomic Origin** | % of reads classified as exonic / intronic / intergenic / overlapping. High intronic/intergenic suggests degraded RNA or protocol issues. |
| **5'→3' Coverage Bias** | Coverage profile across 100 percentile bins of the transcript body. Flat = good; skewed toward one end suggests RNA degradation. |
| **Junction Analysis** | Known vs. novel splice junction counts. |
| **Strand Specificity (SSP)** | Independent strand-specificity estimate from this module — cross-check against `rseqc/{sample}.strandedness.txt` below, which remains the pipeline's actual source of truth for strand. |

---

#### Per-Sample RNA-seq QC Metrics (`rseqc/`)

Everything under `rseqc/` comes from `rustqc` 0.2.1 now, **except** `geneBodyCoverage.txt` and `{regionname}.GC.xls`, which stay on RSeQC directly (`rustqc` doesn't implement those two tools). Output formats/paths for the migrated tools are unchanged from RSeQC's own — text content is byte-for-byte identical to what RSeQC produced, so anything parsing these files doesn't need to change.

##### `rseqc/{sample}.read_distribution.txt`

**Format:** Tab-separated text file (RSeQC-format-identical `rustqc` output)
**Contents:** Read distribution across gene features

| Field | Description |
|---|---|
| CDS_exon | Reads overlapping protein-coding exons (by any base). Count + percentage of total aligned reads. |
| 5'UTR_exon | Reads in 5' untranslated region. |
| 3'UTR_exon | Reads in 3' untranslated region. |
| Intron | Reads spanning intronic regions (indicates potential 3' bias or protocol artifacts if high). |
| Intergenic | Reads in intergenic space (potential contamination or chimeric sequences if high). |

**Interpretation:** Well-sequenced mRNA-seq should show majority of reads in exons (CDS + UTRs); high intronic/intergenic reads suggest issues.

---

##### `rseqc/{sample}.strandedness.txt`

**Format:** Raw text output, RSeQC `infer_experiment.py` format (produced by `rustqc`'s `infer_experiment` module now)

| Content | Description |
|---|---|
| `Fraction of reads explained by "1++,1--,2+-,2-+": X` | **Forward strand fraction** (paired-end). Reads pair orientation consistent with forward strand. |
| `Fraction of reads explained by "1+-,1-+,2++,2--": Y` | **Reverse strand fraction** (paired-end). Reads pair orientation consistent with reverse strand. |
| `Fraction of reads explained by other: Z` | Ambiguous/unstranded reads. |

**Interpretation:** HAROLD uses this to infer strand (> 0.8 fraction = confident; otherwise unstranded). Value is **the source of truth** for strand inference; manifest values override only if `use_infer_strandedness: false`.

---

##### `rseqc/{sample}.geneBodyCoverage.txt` (Best-effort — no longer a required output)

**Format:** Tab-separated text file (RSeQC output — still runs `geneBody_coverage.py` directly; `rustqc` doesn't implement this tool)

| Column | Description |
|---|---|
| Percentile | Position along normalized gene body (0–100). |
| Read Count | Mean read coverage at this percentile (normalized to 1x). |

**Interpretation:** Uniform coverage across all percentiles (flat line) = good quality. 5' or 3' skew (elevation at ends) suggests RNA degradation or protocol bias.

**Note:** This rule reliably fails to complete for some samples in production (RSeQC's `geneBody_coverage.py` can hang/time out on large BAMs) and is **no longer a required output** — the pipeline won't block on it, and it's still runnable standalone if needed. The Qualimap RNA-seq report above (`qualimap_rnaseq/`) provides a working 5'→3' coverage-bias signal for every sample regardless.

---

##### `rseqc/{sample}.Aligned.sortedByCoord.out.summary.txt`

**Format:** Single-line text file with semicolon-delimited metrics (produced by `rustqc`'s `tin` module now)

| Metric | Description |
|---|---|
| Total Exons | Count of exonic regions evaluated. |
| Mean TIN | **Mean Transcript Integrity Number** (0–100). Single-number quality metric. > 80 = excellent; 60–80 = acceptable; < 60 = degraded. |
| Median TIN | Median TIN across transcripts (robust to outliers). |
| StdDev TIN | Standard deviation of TIN scores. |
| Min TIN, Max TIN | Range of per-transcript TIN values. |

**Use case:** Quick per-sample RNA quality check from command line: `grep "Mean TIN" {sample}.Aligned.sortedByCoord.out.summary.txt`

**Note:** TIN now runs at **full read depth** — the BAM downsampling workaround this pipeline previously needed (RSeQC's `tin.py` scaled poorly with read depth) is gone; `rustqc`'s TIN module doesn't need it (benchmarked at ~12 minutes of marginal cost on a 689M-read combined BAM, vs. 7.5–13 hours per sample for RSeQC's `tin.py` on a downsampled input). TIN values from post-migration runs will not match older, downsampled runs byte-for-byte — full depth vs. an ~8–12%-of-data downsample changes the input population by construction.

---

##### `rseqc/{sample}.{regionname}.GC.xls` (Optional)

**Format:** Tab-separated text file (RSeQC output — still runs `read_GC.py` directly; `rustqc` doesn't implement this tool)
**Rows:** One row per GC% bin (0%, 10%, ..., 100%)

| Column | Description |
|---|---|
| GC% | GC content bin. |
| Read Count | Number of reads with this GC content. |
| Expected | Expected count under uniform distribution. |
| Ratio | (Observed / Expected). Values >> 1 indicate GC bias (Illumina reads show GC bias at extremes). |

**Interpretation:** Ratio ≈ 1.0 across all bins = no GC bias (good). Ratio > 1.5 at GC extremes = strong GC bias (may need GC correction in normalization).

---

##### `rseqc/{sample}.{regionname}.junction.bb` (Optional)

**Format:** UCSC BigBed format (binary, compressed BED)
**Contents:** Splice junctions detected in this sample for this region, from `rustqc`'s `junction_annotation` module (`{sample}.{regionname}.junction.bed`, converted to BigBed unchanged)

| Field | Description |
|---|---|
| chrom | Chromosome/contig. |
| chromStart | Junction start (0-based). |
| chromEnd | Junction end. |
| name | Junction ID. |
| score | Junction read count (used for coloring in browser; capped at 1000). |

**Use case:** Load in IGV or UCSC Genome Browser to visualize expressed junctions region-by-region (host vs. per-virus).

---

#### Duplication QC: `dupradar/{sample}_dupMatrix.txt`

**Format:** Tab-separated text file
**Tool:** `rustqc`'s dupRadar module — requires duplicate-marked alignments (see `mark_duplicates` below); net-new QC capability, not present before this migration

| Column | Description |
|---|---|
| `geneLength`, `allCountsMulti`/`allCounts` | Gene length and read counts (multi-mapper-inclusive / unique only). |
| `dupRateMulti`/`dupRate` | **Duplication rate at this gene's expression level** (0–1). |
| `RPKMulti`/`RPKM` | Expression level (reads per kb). |

**Interpretation:** Plot `dupRate` vs. `RPKM` (log scale) — a healthy library shows low, roughly flat duplication rate across expression levels; a steep rise at low expression indicates PCR over-amplification. Also see `dupradar/{sample}_dup_intercept_mqc.txt`/`{sample}_duprateExpDensCurve_mqc.txt` (MultiQC custom-content summaries of the same fit) and the `{sample}_duprateExpBoxplot.png`/`{sample}_duprateExpDens.png` plots.

**Requires duplicate marking:** `mark_duplicates` (Picard) runs on the combined BAM before this module — without it, dupRadar would silently report 0% duplication for every gene, which is misleading rather than merely uninformative. This marked-up BAM is a temporary intermediate, not a pipeline output.

---

#### Library Complexity: `preseq/{sample}.lc_extrap.txt`

**Format:** Tab-separated text file
**Tool:** `rustqc`'s preseq module — net-new QC capability, not present before this migration

| Column | Description |
|---|---|
| `TOTAL_READS` | Sequencing depth (extrapolated beyond the observed data). |
| `EXPECTED_DISTINCT` | Predicted number of distinct (non-duplicate) reads at that depth. |
| `LOWER_0.95CI`/`UPPER_0.95CI` | 95% confidence interval on the prediction. |

**Interpretation:** A curve that keeps rising roughly linearly with `TOTAL_READS` indicates the library still has complexity to give at deeper sequencing; a curve that plateaus early indicates the library is close to fully sequenced (further sequencing would mostly return duplicates).

---

#### featureCounts (QC reference only): `featurecounts/{sample}.featureCounts.tsv`

**Format:** Tab-separated text file, plus `{sample}.biotype_counts.tsv` (biotype breakdown) and MultiQC custom-content variants (`{sample}.biotype_counts_mqc.tsv`, `{sample}.biotype_counts_rrna_mqc.tsv`)
**Tool:** `rustqc`'s featureCounts module — computed internally as a dependency of dupRadar above regardless of whether it's requested, so it's exposed as a reference artifact rather than discarded

**Important:** This is **not** HAROLD's quantification method — gene-level counts for differential expression still come from STAR's own `--quantMode GeneCounts` (`counts_matrix.tsv` below). Treat this file as a QC cross-check / biotype-composition reference only.

#### Pathogen Detection: `kraken2/{sample}.kraken2.report.txt`

**Format:** Kraken2 standard tab-separated report (hierarchical taxonomy)
**Source:** Classification of reads unmapped to primary reference (pass-through from alignment)
**Rows:** Each NCBI taxon ID represented in classified reads

| Column | Data Type | Description |
|---|---|---|
| 1 | Float | **% reads in clade** (sum ≈ 100 at root). Includes all subordinate taxa. |
| 2 | Integer | **Read count in clade**. Direct count (not percentage). |
| 3 | Integer | **Reads assigned directly** to this taxon (not inherited from parent). |
| 4 | String | Rank: superkingdom, phylum, class, order, family, genus, species. |
| 5 | Integer | NCBI taxonomy ID. |
| 6 | String | Scientific name (indented by phylogenetic depth). |

**Example:**
```
100.00	1000000	0	R	1	root
98.50	985000	0	D	2157	Archaea
0.50	5000	5000	S	9606	Homo sapiens
```

**Red flags:**

- **High unclassified reads** (no taxon assigned) → novel sequences, low-complexity regions, or contaminating low-quality bases
- **Unexpected pathogens** → cross-contamination (note: intended viral targets should align to primary reference)
- **Unexpectedly high host (Homo sapiens)** → sample mix-up or contamination
- **Kit-specific contaminants** (common lab bacteria) → reagent contamination

#### Per-Sample Transcript Quantification: `counts/{sample}.rseqc_fpkm_tpm.tsv`

**Format:** Tab-separated text file
**Source:** RSeQC `FPKM_count.py` per-transcript quantification

| Column | Data Type | Description |
|---|---|---|
| 1 | String | **Transcript ID** from reference GTF (ENST accession). |
| 2 | Float | **FPKM** (Fragments Per Kilobase per Million mapped reads). Strand-aware fragment count divided by transcript length and library depth. Comparable across samples (unlike raw counts). May have decimal places. |
| 3 | Float | **TPM** (Transcripts Per Million). Sum of TPM across all transcripts in sample = 1e6. More stable than FPKM across library depth variations. |

**Transformations:** No log transformation. Raw FPKM/TPM output from RSeQC, computed using only primary alignments (MAPQ > 0) overlapping transcript exons, strand-aware.

**Use case:** Aggregated per-sample files are merged into transcript-level count matrices (`counts_matrix.transcript_level.tsv`, etc.) with FPKM/TPM values aggregated across samples.

### FASTQ Validation

| File | Description |
|------|---|
| `fastq_validation/{sample}.fastq_validator.txt` | **FASTQ validation log**, always produced for every sample before Cutadapt runs (not config-gated). Reports any formatting issues with input FASTQ files detected by FastQValidator; a failed validation blocks Cutadapt for that sample. |

---

## Aggregate Output Files

Located in `results/counts/` and `results/`:

### Count Matrices

Count matrices are the primary output for downstream analysis. All are **tab-separated text files** with rows = genes/transcripts and columns = metadata + sample counts.

#### Gene-Level Counts: `counts_matrix.tsv` (Raw Counts)

**Format:** Tab-separated text file
**Rows:** One row per gene/feature (rows are indexed with gene_id|gene_name format)
**Columns:** Metadata columns + one column per sample

| Column Position | Column Name | Data Type | Description |
|---|---|---|---|
| 1 | `(index)` | String | **Gene identifier** in format `ENSG00000123456.11\|BRCA1` (gene_id\|gene_name). Gene ID is RefSeq/Ensembl accession; gene_name is human-readable name (or "NA" if unavailable). |
| 2 | `species` | String | **Genome origin**: `hg38`, `mm39`, or viral accession ID (e.g., `NC_009333.1`). Identifies which reference genome this gene belongs to. |
| 3 | `gene_chr` | String | **Chromosome/contig** where gene is located (e.g., `chr1`, `NC_009333.1:1-137895`). |
| 4 | `gene_start` | Integer | **0-based gene start coordinate** in the reference genome. |
| 5 | `gene_end` | Integer | **0-based gene end coordinate** (exclusive). |
| 6 | `gene_strand` | String | **Strand orientation**: `+` (forward) or `-` (reverse). |
| 7 | `gene_length_kb` | Float | **Gene length in kilobases** (kb). Calculated as sum of exon lengths per gene (spliced length, not genomic span). **Used for RPKM/TPM normalization.** Units: kilobases, 3 decimal places. |
| 8 | `gene_type` | String | **Gene biotype** from GTF: `protein_coding`, `lncRNA`, `miRNA`, `tRNA`, `rRNA`, etc. |
| 9+ | `{sample_name}` | Integer | **Raw read count** for this gene in this sample. Counts are the number of uniquely mapped reads (MAPQ ≥ 255) that overlap the gene's exons. **NOT log-transformed; directly from STAR ReadsPerGene.out.tab after strand selection.**  |

**Example row:**
```
ENSG00000000003.15|ENSG00000000003	hg38	chrX	99883667	99894976	-	11.31	protein_coding	42	58	101	73
```
Interpretation: Gene ENSG00000000003 on chrX, 11.31 kb, 42 reads in sample 1, 58 in sample 2, etc.

**Transformations applied:** None. Raw counts directly from STAR, selected by strand (inferred or from manifest), with STAR's "N_" metadata rows (unmapped, ambiguous) removed.

---

#### Gene-Level Counts: `counts_matrix.rpkm.tsv` (RPKM Normalized)

**Format:** Tab-separated text file (same column structure as `counts_matrix.tsv`)
**Normalization:** RPKM = (ReadCount / GeneLength_kb) / (Total_Mapped_Millions)

**Formula per sample:**
```
RPKM[gene][sample] = (Count[gene][sample] / gene_length_kb) / (sum_all_genes(Count[gene][sample]) / 1e6)
```

| Column | Data Type | Description |
|---|---|---|
| 1–8 | *Same as raw counts* | Metadata columns identical to `counts_matrix.tsv`. |
| 9+ | Float | **RPKM-normalized counts**. Accounts for gene length and sequencing depth. Range: 0–10000+ (no fixed upper bound). **Not recommended for statistical testing**, but useful for qualitative comparisons. Can be small (< 0.1) for lowly expressed genes. |

**Example:** RPKM = 5.23 means 5.23 reads per kilobase of gene per million mapped reads in that sample.

---

#### Gene-Level Counts: `counts_matrix.tpm.tsv` (TPM Normalized)

**Format:** Tab-separated text file (same column structure as `counts_matrix.tsv`)
**Normalization:** TPM = (RPKM / sum_all_genes(RPKM)) × 1e6

| Column | Data Type | Description |
|---|---|---|
| 1–8 | *Same as raw counts* | Metadata columns identical to `counts_matrix.tsv`. |
| 9+ | Float | **TPM-normalized counts**. Transcripts Per Million. **Sum of all TPM values in a sample = 1,000,000 by definition.** Easier to interpret than RPKM: "per gene, out of 1 million transcripts in the cell, how many are from this gene?" Range: 0–10000+ with sum = 1M per sample. Not recommended for statistical testing. |

**Example:** TPM = 250.5 means 250.5 genes per million transcripts in that sample (roughly 1 in 4000 total transcripts).

---

#### Gene-Level Sample Strandedness: `sample_strandedness.tsv`

**Format:** Tab-separated text file, no index column
**Rows:** One row per sample (in order of input samples)

| Column | Data Type | Description |
|---|---|---|
| 1 | `sample` | String | **Sample name** exactly as it appears in `samples.tsv` and output directory names. |
| 2 | `inferred_strand` | String | **Strandedness inferred by `rustqc`'s `infer_experiment` module** (from read pair orientation): `forward`, `reverse`, or `unstranded`. This is what the RNA-seq library actually shows. |
| 3 | `used_strand` | String | **Strandedness USED for count extraction**: either the inferred value or value from manifest, depending on config key `use_infer_strandedness`. If `true` (default), = inferred_strand. If `false`, = value from manifest or inferred if manifest missing. |
| 4 | `inference_fraction` | Float | **Confidence of strand inference** (0.0–1.0). Fraction of read pairs that show the inferred strand orientation. Higher = more confident (> 0.8 is good; ~0.5 means ambiguous/unstranded). Used internally to decide unstranded threshold (default 0.8). |

**Example row:**
```
sample_A	forward	forward	0.95
sample_B	unstranded	unstranded	0.52
```
Interpretation: Sample A confidently forward-stranded (95% of pairs); Sample B ambiguous (only 52% show any bias).

---

#### Transcript-Level Counts: `counts_matrix.transcript_level.tsv`

**Format:** Tab-separated text file
**Rows:** One row per unique transcript (from GTF transcript_id)
**Columns:** Metadata + per-sample counts

| Column Position | Column Name | Data Type | Description |
|---|---|---|---|
| 1 | `(index)` | String | **Transcript identifier** in format `ENST00000456328.2\|RP11-34P13.7` (transcript_id\|gene_name). |
| 2 | `gene_id` | String | Parent gene ID for this transcript. |
| 3 | `gene_name` | String | Human-readable gene name. |
| 4 | `chrom` | String | **Chromosome** where transcript is located. |
| 5 | `tx_start` | Integer | **0-based transcript start** coordinate. |
| 6 | `tx_end` | Integer | **0-based transcript end coordinate** (exclusive). |
| 7+ | `{sample_name}` | Integer | **Per-transcript read count** from RSeQC FPKM_count output. Reads that overlap exons of this transcript (strand-aware). Lower values than gene-level counts due to no aggregation. |

**Transformations applied:** Raw counts from RSeQC's FPKM_count per-transcript output, aggregated across all samples.

---

#### Transcript-Level Counts (Normalized): `counts_matrix.transcript_level.rpkm.tsv` & `.tpm.tsv`

**Format:** Same structure as transcript-level raw counts, but with RPKM / TPM normalization applied

| Column | Data Type | Description |
|---|---|---|
| 1–6 | *Same as raw* | Metadata columns. |
| 7+ | Float | **RPKM or TPM normalized** using same formulas as gene-level counts (normalize by transcript length). |

### Alignment Quality Summary: `alignmentqc/alignment_summary.tsv`

**Format:** Tab-separated text file with header row
**Rows:** One row per sample (in directory scan order, typically alphabetical)

| Column | Data Type | Description | Source |
|---|---|---|---|
| `sample` | String | **Sample name** from directory name. | Sample directory listing |
| `library_type` | String | **Sequencing library type**: `PE` (paired-end) or `SE` (single-end). Inferred from Cutadapt output. | Cutadapt report |
| `total_reads` | Integer | **Total number of reads** in input FASTQ file(s) before trimming. For PE: total read PAIRS (counts as 1); for SE: read count directly. | FastQValidator report |
| `trimmed_reads` | Integer | **Reads passing Cutadapt** after quality/adapter trimming. Same definition as total_reads (pairs for PE, reads for SE). To get trimming rate: (trimmed_reads / total_reads) × 100. | Cutadapt report |
| `reads_mapped_to_assembly` | Integer | **Total reads mapped** to the reference assembly (uniquely + multi-mapped + too_many_loci). Calculated as sum of: uniquely_mapped + multi_mapped + too_many_loci. For PE libraries, multiplied by 2 (each pair = 2 reads). | STAR Log.final.out |
| `uniquely_mapped_reads` | Integer | **Uniquely mapped reads** (MAPQ ≥ 255, no secondary/supplementary alignments). These are the reads used in count matrices. For PE: multiplied by 2. | STAR Log.final.out |
| `multi_mapped_reads` | Integer | **Multi-mapped reads** (mapped to 2–249 loci equally). Not used in counts. For PE: multiplied by 2. | STAR Log.final.out |
| `too_many_loci_reads` | Integer | **Reads mapping to too many loci** (250+). Filtered out. For PE: multiplied by 2. | STAR Log.final.out |
| `host_mapped` | Integer | **Primary alignments to host genome** (e.g., hg38, mm39). Counted from BAM file primary alignment flag. |  BAM analysis |
| `chrR_mapped` | Integer | **Primary alignments to chrR regions** (repeats, rRNA, etc.) if present. Subset of host_mapped. | BAM analysis |
| `{virus_accession}_mapped` | Integer | **Primary alignments to each virus** (one column per virus, e.g., NC_009333.1_mapped, NC_045512.2_mapped). Named by RefSeq accession ID. | BAM analysis |
| `{additive}_mapped` | Integer | **Primary alignments to each additive/spike-in** (one column per configured additive, e.g., ERCC_mapped, BAC16Insert_mapped, 4SU1_mapped). Named by additive name. | BAM analysis |

**Example row:**
```
sample_A	PE	50000000	48000000	47500000	46000000	1200000	300000	45000000	5000	2500000	250000	150000
```
Interpretation: Sample A, paired-end, 50M raw pairs → 48M trimmed (96% pass) → 47.5M mapped → 46M unique (96.8% uniquely map). 45M map to host, 2.5M to virus1, 250K to virus2.

**Mapping rate calculation:** (reads_mapped_to_assembly / trimmed_reads) × 100
**Unique mapping rate:** (uniquely_mapped_reads / reads_mapped_to_assembly) × 100

---

### RNA Quality: Transcript Integrity Number Aggregate

#### Per-Transcript TIN Details: `{sample}/{sample}.Aligned.sortedByCoord.out.tin.xls`

**Format:** Tab-separated text file with header row, RSeQC-format-identical (produced by `rustqc`'s `tin` module now, at full read depth — see the full-depth note above)
**Rows:** One row per transcript detected in the BAM file

| Column | Data Type | Description |
|---|---|---|
| `geneID` | String | **Transcript ID** from reference GTF. |
| `chrom` | String | **Chromosome** where transcript is located. |
| `tx_start` | Integer | **Transcript start** coordinate (0-based). |
| `tx_end` | Integer | **Transcript end** coordinate (exclusive). |
| `TIN` | Integer | **Transcript Integrity Number** (0–100 scale). Measures read coverage uniformity across transcript body. Higher = more uniform coverage = better RNA quality. Interpretation: > 80 = excellent, 60–80 = acceptable, < 60 = degraded/non-uniform. |
| Additional columns | | Other metrics (median_cv, min_cv, etc.); the TIN column is the primary metric for quality assessment. |

---

#### Aggregate TIN Summary: `counts/aggregate_tin.tsv`

**Format:** Tab-separated text file with header row
**Rows:** One row per transcript (merged across all samples)

| Column | Data Type | Description |
|---|---|---|
| `geneID` | String | **Transcript ID** from GTF. |
| `chrom` | String | **Chromosome** where transcript is located. |
| `tx_start` | Integer | **Transcript start coordinate** (0-based). |
| `tx_end` | Integer | **Transcript end coordinate** (exclusive). |
| `{sample_name}` | Integer or NaN | **TIN score for this transcript in this sample** (0–100), or NaN if transcript not covered in that sample. |

**Example row:**
```
ENST00000456328.2	chr1	100000	101000	85	79	82	NaN	88
```
Interpretation: Transcript ENST00000456328.2, excellent quality in samples 1,3,5 (TIN ≥ 79); not detected in sample 4.

**Quality assessment:** Calculate mean TIN per sample across all rows:

- **Mean TIN > 80:** Excellent RNA quality
- **Mean TIN 60–80:** Acceptable quality
- **Mean TIN < 60:** Poor RNA quality; consider re-extraction
- **Many NaN values:** Sample has low coverage; may not be representative

### MultiQC Report

| File | Description |
|------|---|
| `multiqc_report.html` | **Interactive HTML dashboard** aggregating QC metrics from FastQC, Cutadapt, STAR, `rustqc` (RSeQC-equivalent modules, dupRadar, preseq, featureCounts), the genomic and RNA-seq Qualimap reports, and Kraken2 across all samples. **Start here for a high-level overview of experiment quality.** Open in any web browser; includes interactive plots, tables, and cross-sample comparisons. |
| `multiqc_data/` | **Data tables and configuration files** backing the MultiQC report. JSON and YAML files that can be parsed programmatically if needed. |

---

## Optional Outputs

### Normalized Count Matrices (DiffEx Integration)

Only generated if `diffex_normalized_counts: true` in config. `{variant}` is always `{wo_ercc|w_ercc}_{wo_batch|w_batch}` (e.g. `wo_ercc_wo_batch`, `w_ercc_w_batch`) — the same shared `diffex.use_ercc`/`diffex.use_batch` tri-state options that drive DEG/GSEA below also drive this step, so `both` produces every variant side by side here too.

| File | Description |
|------|---|
| `counts/normalized_counts/{variant}/normalize.html` | **DiffEx-normalized count matrix report**, across the whole sample set. HTML report with normalized counts using DiffEx package (ERCC-based spike-in normalization, batch effect correction, etc.), per the `diffex` config block in `config.yaml`. |

### DEG and GSEA (DiffEx Integration)

Only generated if `diffex_deg_gsea: true` in config, and requires a `contrasts.tsv` file (tab-delimited, `group1`/`group2` columns) listing which `groupName` pairs from `samples.tsv` to compare. `{contrast}` is `{group1}_vs_{group2}`. `{variant}` is always `{wo_ercc|w_ercc}_{wo_batch|w_batch}` (e.g. `wo_ercc_wo_batch`, `w_ercc_w_batch`), so the directory name alone always shows whether ERCC/batch correction was applied — regardless of whether `use_ercc`/`use_batch` is set to `true`, `false`, or `both`. The tri-state `use_ercc`/`use_batch` config options (shared with the normalized-counts step above, via the `diffex` config block) run DEG once per selected state, so `both` produces every variant side by side rather than picking one.

| File | Description |
|------|---|
| `counts/DEG/{contrast}_{variant}/{method}_deg/{method}_results.tsv` | **Differential expression results** for one contrast/variant, from one of `limma`, `DESeq2`, or `edgeR` (casing matches the `diffex deg` tool's own output naming). |
| `counts/DEG/{contrast}_{variant}/{method}_deg/{method}_gsea.rnk` | **Ranked gene list** derived from the DEG results, used as input to the GSEA step below. |
| `counts/GSEA/{contrast}_{variant}/{method}/GSEA_results.xlsx` | **GSEA enrichment results** for the corresponding `.rnk` file. |
| `counts/GSEA/{contrast}_{variant}/{method}/gsea.html` | **Interactive GSEA report** for the corresponding `.rnk` file. |

### S3 Transfer Sentinel

| File | Description |
|------|---|
| `.s3_transfer.done` | **Marker file** (created only if `push_to_s3: true` AND `s3_sample_set_name` is non-empty in config). Indicates that all outputs have been successfully uploaded to the configured S3 bucket. Check `results/logs/` for detailed upload logs if transfer fails. See [S3 Configuration Guide](s3_configuration.md) for setup, cost estimation, and troubleshooting. |

---

## Output Naming Conventions

### Sample Names

All per-sample files use the exact sample name from your `samples.tsv` manifest. Ensure sample names are:

- **Unique** across the experiment
- **URL-safe** (avoid spaces, special characters, or use underscores/hyphens)
- **Consistent case** (e.g., all lowercase or CapitalCase)

### Genomic Region Names

Files containing region-specific outputs use region identifiers:

- **Host:** `hg38` or `mm39` (depending on your host genome)
- **Viruses:** RefSeq accession IDs (e.g., `NC_009333.1` for KSHV, `NC_045512.2` for SARS-CoV-2)
- **Additives:** `ERCC`, `BAC16Insert`, `4SU1` (if included)

Example: `{sample}.NC_009333.1.bam` contains only reads mapped to KSHV.

---

## How to Use These Outputs

### For Differential Expression Analysis

1. **Start with:** `counts/counts_matrix.tsv` (raw counts)
2. **Input to:** DESeq2 (R/Bioconductor) or edgeR
3. **Reference:** `counts_matrix.rpkm.tsv` or `.tpm.tsv` for qualitative interpretation

### For Quality Assessment

1. **Quick overview:** Open `multiqc_report.html` in a web browser
2. **Sample-level detail:** Check `results/{sample}/rseqc/{sample}.Aligned.sortedByCoord.out.summary.txt` for TIN scores
3. **Alignment stats:** Review `alignmentqc/alignment_summary.tsv` for mapping rates and trimming statistics

### For Visualization

1. **Browser-based (UCSC, IGV):** Use `results/{sample}/bigwigs/{sample}.*.bw` files
2. **R/Bioconductor:** Load BAM files with Rsamtools; use coverage functions with BigWig tracks
3. **Custom analysis:** BAM files (`results/{sample}/STAR/{sample}.Aligned.sortedByCoord.out.bam`) are standard SAM-format files compatible with any alignment analysis tool

### For Downstream Integration

1. **DiffEx pipeline:** Supply `counts/counts_matrix.tsv` and `samples.tsv`
2. **SEQC-compatible:** All outputs follow standard naming and location conventions
3. **Custom scripts:** Manifest (`samples.tsv`), counts (TSV), and configuration (`config.yaml`) are human-readable for parsing

---

## Frequently Asked Questions

**Q: Which count matrix should I use for differential expression?**
A: Use `counts_matrix.tsv` (raw counts). Pass this directly to DESeq2 or edgeR, which apply their own normalization internally. Do NOT use RPKM or TPM counts for statistical testing.

**Q: What does TIN (Transcript Integrity Number) mean?**
A: TIN scores range 0–100, where higher = better RNA quality. Samples with mean TIN > 80 have excellent RNA; 60–80 is acceptable; < 60 suggests RNA degradation. Check `counts/aggregate_tin.tsv` for quick assessment.

**Q: Why do some reads map to multiple regions (host + viruses)?**
A: Some sequences (e.g., highly conserved genes) may have homology across regions. STAR reports primary alignment; split BAM files (`{sample}.{region}.bam`) contain only reads with unique primary alignment to that region. Multi-mapped reads may appear in multiple region-specific files.

**Q: Can I use BigWig files in IGV?**
A: Yes. Download all `.bw` files from `results/{sample}/bigwigs/` and load them into IGV alongside the corresponding BAM file for integrated visualization of coverage and reads.

**Q: How do I know if strandedness was correctly inferred?**
A: Check `results/{sample}/rseqc/{sample}.strandedness.txt`. If one strand shows > 80% bias, inference is confident. If percentages are ~50/50, the library is unstranded or sense/antisense assignments are ambiguous. Review the manifest if known strandedness differs from inferred values.

---

## Troubleshooting

**Missing outputs:**

- Check logs under `logs/` for rule-specific errors. Search for the output name in the log tree: `find logs -name "*outputname*"`
- Verify input files exist and are readable: `ls -la results/{sample}/STAR/`
- Re-run a dry-run to identify missing dependencies: `harold -w <workdir> -m dryrun`

**Unexpected file sizes:**

- Large BAM files (> 50 GB) are normal for high-coverage samples. Use `samtools stats` to verify integrity.
- Small or empty count matrices may indicate low mapping rates. Check `alignment_summary.tsv` for mapping statistics.

**Quality concerns:**

- Low TIN scores → RNA degradation (consider re-extracting RNA)
- Low mapping rate → check Cutadapt report for contamination; verify reference selection
- Unexpected viral reads → cross-check with Kraken2 report; may indicate contamination or novel sequences

