# ☁️ S3 Output Deposition

HAROLD can automatically deposit pipeline outputs to Amazon S3 buckets, enabling cloud storage, sharing, and downstream analysis without local disk overhead. This page covers setup, configuration, monitoring, and troubleshooting.

---

## Prerequisites

### **Globus Account and S3 Bucket Access**

HAROLD uses a **lab-managed service account** linked to Globus for S3 access. You do **not** need an individual AWS account.

**Requirements:**

1. **Globus Account:** Create a Globus account if you don't have one (free, institutional login supported)
2. **Globus Connector Access:** The lab's S3 bucket (`dremel-lab-bucket`) is accessible via a Globus connector. The S3 bucket will appear in your Globus file browser after your account is linked.

**If you don't have Globus access or the S3 bucket doesn't appear in your Globus:** See the [S3 & Globus Access Guide](https://dremellab.github.io/howtos/guides/s3-globus-access/s3_globus_access_guide.html) for instructions on setting up your Globus account and requesting connector access.

### **S3 Credentials (Lab-Managed)**

HAROLD uses lab-managed AWS credentials stored in a shared, secure location. These credentials are automatically configured on Rivanna in the pipeline environment. **You do not need to create or manage credentials yourself.**

**Credential renewal:** Lab credentials expire every 90 days. If your S3 downloads via Globus or Uploads fail with authentication errors, reach out via email and the lab will update the credentials for you to re-enter on Globus.

---

## Configuration in `config.yaml`

### **S3 Settings Block**

Add or update the following in your `config.yaml`:

```yaml
# S3 Output Deposition (optional)
push_to_s3: false                          # Set to true to enable S3 transfer
s3_sample_set_name: ""                     # Required if push_to_s3=true (user-friendly name for this run)
s3_pipeline_name: "HAROLD"                 # Pipeline identifier in S3 path (do not change)
s3_aws_credentials_file: "/project/dremel_lab/scripts/aws/credentials"  # Lab-managed credentials (do not change)
s3_bucket: "dremel-lab-bucket"             # Lab S3 bucket (do not change)
s3_output_prefix: "_HTS"                   # Bucket prefix (do not change)
s3_default_storage_class: "GLACIER_IR"     # Storage class (do not change)
s3_large_file_storage_class: "GLACIER"     # Storage class for large files (do not change)
```

### **Configuration Details**

| Key | Type | Default | Required? | Description |
|---|---|---|---|---|
| `push_to_s3` | Boolean | `false` | No | Enable/disable S3 transfer. If `false`, all other S3 keys ignored. |
| `s3_sample_set_name` | String | `""` | **Yes, if push_to_s3=true** | Must match `sampleSetName` in lookup.tsv on Rivanna |
| `s3_pipeline_name` | String | `HAROLD` | — | Pipeline identifier in S3 path. **Do not change.** |
| `s3_aws_credentials_file` | String | `/project/dremel_lab/scripts/aws/credentials` | — | Lab-managed credentials. **Do not change.** Email lab if expired. |
| `s3_bucket` | String | `dremel-lab-bucket` | — | Lab S3 bucket for all outputs. **Do not change.** |
| `s3_output_prefix` | String | `_HTS` | — | Bucket prefix. **Do not change.** |
| `s3_default_storage_class` | String | `GLACIER_IR` | — | Storage class for metadata. **Do not change.** |
| `s3_large_file_storage_class` | String | `GLACIER` | — | Storage class for BAM files. **Do not change.** |

---

## S3 Path Hierarchy

HAROLD organizes outputs in a hierarchical S3 path structure:

```
s3://{bucket}/{s3_output_prefix}/{s3_pipeline_name}/{s3_sample_set_name}/{output_type}/...
```

**Example:**
```
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/config/samples.tsv
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/config/config.yaml
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/qc/multiqc_report.html
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/qc/alignment_summary.tsv
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/bams/{sample}.Aligned.sortedByCoord.out.bam
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/bams/{sample}.Aligned.sortedByCoord.out.bam.bai
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/bigwigs/{sample}.{region}.bw
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/peaks/{sample}.*
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/counts/counts_matrix.tsv
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/counts/counts_matrix.rpkm.tsv
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/counts/counts_matrix.tpm.tsv
s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/deseq2/...
```

**Namespace benefits:**

- **Scoping:** Each pipeline (HAROLD, CHROMA, etc.) isolated; multiple runs grouped by sample_set_name
- **Organizing:** Outputs are easily located within the bucket structure

---

## Files Transferred to S3

HAROLD transfers the following output types:

| Category | Files | Storage Class | Reason |
|---|---|---|---|
| **Configuration** | `samples.tsv`, `config.yaml`, `contrasts.tsv` | GLACIER_IR | Metadata for reproducibility |
| **QC Reports** | `multiqc_report.html`, `alignment_summary.tsv`, MultiQC data | GLACIER_IR | High-level summary; quick access for review |
| **Alignment QC** | Qualimap reports, RSeQC outputs, ataqv data | GLACIER_IR | Supplementary QC; browseable |
| **BAM Files** | `.bam`, `.bai` (all samples, all regions) | GLACIER | Large files; infrequent access; ~1 min retrieval acceptable |
| **BigWig Tracks** | `.bw` (all samples, all regions) | GLACIER_IR | Visualization; medium size; instant retrieval useful |
| **Peak Files** | `.narrowPeak.gz`, `.summits.bed.gz` | GLACIER_IR | Region annotations |
| **Count Matrices** | `counts_matrix.tsv`, RPKM, TPM, transcript-level | GLACIER_IR | Primary output for analysis |
| **DESeq2 Reports** | `deseq2/` directory (HTML reports, TSVs) | GLACIER_IR | Analysis results; browseable |
| **tRNA/Tn5 Counts** | Aggregate count matrices, PFMs, BigBeds | GLACIER_IR | Specialized quantification |

**Total typical upload size:** 50–500 GB per run (scales with read count and number of samples)

---

## Enabling and Running S3 Transfer

### **Step 1: Update `config.yaml`**

```yaml
push_to_s3: true
s3_sample_set_name: "exp_A_batch1"  # Choose a meaningful name
```

### **Step 2: Initialize and Run Normally**

```bash
harold -w=/scratch/$USER/harold_run -m=init \
  --host=hg38 \
  --viruses=NC_009333.1 \
  --manifest=/path/to/samples.tsv

harold -w=/scratch/$USER/harold_run -m=dryrun
harold -w=/scratch/$USER/harold_run -m=run
```

**What happens:**

- Pipeline runs as normal
- Upon successful completion of all prior stages, S3 transfer rule (`s3_transfer_if_enabled`) is triggered
- Outputs transferred to S3 with configured storage classes
- Sentinel file `.s3_transfer.done` created in work directory on success

### **Step 3: Verify Transfer**

Check for the sentinel file:
```bash
ls -la /scratch/$USER/harold_run/.s3_transfer.done
```

List uploaded objects:
```bash
aws s3 ls s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/ --recursive
```

Check S3 file count and size:
```bash
aws s3 ls s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/ --recursive --summarize
```

---


---

## Troubleshooting S3 Transfer

### **Transfer Failed or Hung**

**Symptom:** Snakemake rule `s3_transfer_if_enabled` fails or times out

**Debug steps:**
1. Check Snakemake logs: `cat logs/rule_s3_transfer_if_enabled/*/7*.log` (substitute SLURM job ID)
2. Verify credentials: `aws sts get-caller-identity` (should print your AWS account)
3. Test manual S3 upload:
   ```bash
   echo "test" | aws s3 cp - s3://dremel-lab-bucket/test.txt
   aws s3 rm s3://dremel-lab-bucket/test.txt
   ```
4. Check network connectivity: `ping -c 1 s3.amazonaws.com`

**Common issues:**

- **Credentials not found:** Check `s3_aws_credentials_file` in config.yaml
- **Access denied:** Email the lab for credential updates or verification
- **Network timeout:** Check Rivanna outbound S3 access (may require VPN or firewall exception)

### **Partial Transfer (Some Files Missing)**

**Symptom:** Some outputs uploaded, others missing; sentinel file doesn't exist

**Debug:**
1. Check rule logs for errors: `grep -i error logs/rule_s3_transfer_if_enabled/*/7*.log`
2. List uploaded vs. local outputs:
   ```bash
   aws s3 ls s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/bams/ --recursive | wc -l
   find results -name "*.bam" | wc -l
   ```
3. Re-run S3 transfer manually (idempotent):
   ```bash
   python3 workflow/scripts/s3_transfer_harold.py \
     --workdir . --pipeline-name HAROLD --sample-set-name exp_A_batch1
   ```

### **Cost Overruns**

**Issue:** S3 bills higher than expected

**Investigate:**
1. Check storage class distribution: `aws s3api list-objects-v2 --bucket dremel-lab-bucket --prefix '_HTS/HAROLD' --query 'Contents[].StorageClass' | sort | uniq -c`
2. Identify large files: `aws s3 ls s3://dremel-lab-bucket/_HTS/HAROLD/ --recursive --summarize | tail -20`

---

## Best Practices

1. **Use meaningful `s3_sample_set_name`:** Ensure it matches the `sampleSetName` in lookup.tsv on Rivanna. This name will become a subfolder in S3 containing all outputs for this run.
2. **Enable S3 for production runs only:** Set `push_to_s3: false` for test/debugging runs to avoid cluttering S3

---

## See Also

- [Usage Guide](usage.md) — S3 transfer as final pipeline step
- [S3 & Globus Access Guide](https://dremellab.github.io/howtos/guides/s3-globus-access/s3_globus_access_guide.html) — Setting up Globus and requesting S3 bucket access
- [Outputs](outputs.md) — Detailed description of transferred files
