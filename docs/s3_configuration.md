# ☁️ S3 Output Deposition

HAROLD can automatically deposit pipeline outputs to Amazon S3 buckets, enabling cloud storage, sharing, and downstream analysis without local disk overhead. This page covers setup, configuration, monitoring, and troubleshooting.

---

## Prerequisites

### **AWS Account and S3 Bucket**

1. **AWS Account:** Must have an active AWS account with S3 permissions
2. **S3 Bucket:** Create or designate an existing S3 bucket for HAROLD outputs
   - Bucket must exist before initialization
   - User credentials must have `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` permissions
   - Recommend bucket versioning and lifecycle policies for long-term retention

**If you don't have direct S3 bucket access:** See the [S3 & Globus Access Guide](https://dremellab.github.io/howtos/guides/s3-globus-access/s3_globus_access_guide.html) for instructions on requesting access to the lab-managed S3 bucket via Globus or alternative credential setup methods.

### **AWS Credentials**

HAROLD uses AWS CLI v2 (bundled in the `aws` container). Credentials can be provided via:

#### **Option 1: Credentials File (Recommended)**
Store credentials in `~/.aws/credentials` or custom path:
```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
```

Or set environment variables:
```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
```

#### **Option 2: IAM Role (Rivanna-Specific)**
If running on Rivanna with lab-managed IAM roles, credentials can be auto-discovered via role assumption (configure via Rivanna HPC admin).

#### **Securing Credentials**

⚠️ **Important:** Credentials file should **never be committed to Git**. Ensure `.gitignore` includes:
```
.aws/credentials
AWS_SECRET_ACCESS_KEY
```

Recommend:
- Store credentials in `/project/dremel_lab/scripts/aws/credentials` (lab-managed, accessible but not in repo)
- Set file permissions: `chmod 600 ~/.aws/credentials`
- Rotate credentials regularly (AWS best practice: every 90 days)
- Use IAM role assumption over long-lived credentials when possible

---

## Configuration in `config.yaml`

### **S3 Settings Block**

Add or update the following in your `config.yaml`:

```yaml
# S3 Output Deposition (optional)
push_to_s3: false                          # Set to true to enable S3 transfer
s3_pipeline_name: "HAROLD"                 # Pipeline identifier in S3 path
s3_sample_set_name: ""                     # Required if push_to_s3=true (user-friendly name for this run)
s3_aws_credentials_file: "/project/dremel_lab/scripts/aws/credentials"  # Path to AWS credentials
s3_bucket: "dremel-lab-bucket"             # S3 bucket name
s3_output_prefix: "_HTS"                   # Prefix in bucket (customize if needed)
s3_default_storage_class: "GLACIER_IR"     # Storage class for most files
s3_large_file_storage_class: "GLACIER"     # Storage class for large files (BAMs)
```

### **Configuration Details**

| Key | Type | Default | Required? | Description |
|---|---|---|---|---|
| `push_to_s3` | Boolean | `false` | No | Enable/disable S3 transfer. If `false`, all other S3 keys ignored. |
| `s3_pipeline_name` | String | `HAROLD` | If push_to_s3=true | Pipeline identifier; inserted into S3 path hierarchy. Use consistent name across runs. |
| `s3_sample_set_name` | String | `""` | **Yes, if push_to_s3=true** | User-friendly identifier for this run (e.g., `exp_A_batch1`, `coinfection_2024`). **Pipeline will not run if empty and push_to_s3=true.** |
| `s3_aws_credentials_file` | String | `/project/dremel_lab/scripts/aws/credentials` | No | Path to AWS credentials file. If not found, falls back to `~/.aws/credentials` and environment variables. |
| `s3_bucket` | String | `dremel-lab-bucket` | No | S3 bucket name (without `s3://` prefix). Must exist and be accessible with provided credentials. |
| `s3_output_prefix` | String | `_HTS` | No | Prefix in bucket hierarchy. Customize to namespace different projects/pipelines at bucket root. |
| `s3_default_storage_class` | String | `GLACIER_IR` | No | Storage class for most outputs: `STANDARD`, `STANDARD_IA`, `GLACIER_IR`, `GLACIER`, `DEEP_ARCHIVE`. **GLACIER_IR recommended for cost (infrequent access, instant retrieval).** |
| `s3_large_file_storage_class` | String | `GLACIER` | No | Storage class for large files (BAM/BAI, > 1 GB): `GLACIER`, `DEEP_ARCHIVE`. **GLACIER recommended for large files (cheaper long-term, ~1 min retrieval time).** |

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
- **Access control:** IAM policies can restrict access by path prefix (e.g., `_HTS/HAROLD/*` for HAROLD-only access)
- **Cost allocation:** AWS tagging and cost allocation rules can track spending per pipeline/sample-set

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

## Dry-Run Mode for S3 Planning

Before committing large uploads, preview what will be transferred:

### **Enable Dry-Run in S3 Transfer Script**

Modify the Snakemake invocation to pass `--dry-run` flag to the S3 script (if needed). Alternatively, manually preview:

```bash
cd /scratch/$USER/harold_run

# List files that WOULD be transferred (without uploading)
python3 workflow/scripts/s3_transfer_harold.py \
  --workdir . \
  --pipeline-name HAROLD \
  --sample-set-name exp_A_batch1 \
  --bucket dremel-lab-bucket \
  --s3-prefix _HTS \
  --dry-run
```

**Output:** Prints S3 paths and file sizes for all outputs that would be uploaded. Useful for:
- Estimating upload time and storage costs
- Verifying namespace hierarchy before committing
- Identifying missing or unexpected files

---

## Storage Classes and Costs

### **Storage Class Selection**

Choose based on **access frequency** and **cost tolerance**:

| Class | Cost (per GB/month) | Retrieval | Use Case | HAROLD Default |
|---|---|---|---|---|
| **STANDARD** | $0.023 | Instant | Frequent access, hot data | Not used |
| **STANDARD_IA** | $0.0125 | Instant | Infrequent access, instant retrieval needed | Not used |
| **GLACIER_IR** | $0.004 | Instant | Infrequent access, occasional review | ✅ Most files |
| **GLACIER** | $0.0036 | 1–5 min | Archive, rare retrieval | ✅ BAMs |
| **DEEP_ARCHIVE** | $0.00099 | 12 h | Long-term archive, compliance | Not used |

### **Cost Estimate Example**

For a 100-sample run, 100M reads per sample:

| File Type | Count | Size | Storage Class | Cost/month |
|---|---|---|---|---|
| BAM + BAI | 200 | 100 GB | GLACIER | $0.36 |
| BigWigs | 400 | 20 GB | GLACIER_IR | $0.08 |
| Count matrices | 1 | 1 GB | GLACIER_IR | $0.004 |
| QC reports | ~100 | 2 GB | GLACIER_IR | $0.008 |
| **Total** | — | ~123 GB | — | **~$0.45/month** |

**Annual cost for 10 runs:** ~$54/year (negligible compared to compute costs)

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
- **Credentials not found:** Check `~/.aws/credentials` or `s3_aws_credentials_file` in config.yaml
- **Access denied:** Verify IAM permissions (GetObject, PutObject, ListBucket on bucket)
- **Bucket doesn't exist:** Create bucket first: `aws s3 mb s3://dremel-lab-bucket`
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
3. Consider lifecycle policies to auto-transition to cheaper storage after 30 days (GLACIER → DEEP_ARCHIVE)

---

## Advanced: Custom S3 Configurations

### **Using Different Buckets per Sample Set**

Instead of all outputs in one bucket, partition by sample-set or project:

```yaml
push_to_s3: true
s3_sample_set_name: "exp_A_batch1"
s3_bucket: "dremel-lab-bucket-projectA"  # Different bucket per project
s3_output_prefix: "_HTS"
```

**Benefit:** Isolate access control per project; easier billing per customer/collaborator

### **Cross-Account S3 (Multi-Lab Collaboration)**

If uploading to a different AWS account's bucket:
1. Configure cross-account IAM role in receiving account
2. Set credentials to assume that role (via `aws sts assume-role`)
3. Update `s3_aws_credentials_file` or environment variables with temporary credentials from role assumption

---

## Integration with Downstream Analysis

### **Direct S3 Analysis (No Local Download)**

Many tools support S3 paths directly:

**R/Bioconductor (DESeq2, etc.):**
```r
# Read counts matrix from S3 without downloading
library(aws.s3)
counts <- read.csv(
  "s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/counts/counts_matrix.tsv",
  sep="\t"
)
```

**Python (Pandas, Scanpy):**
```python
import pandas as pd
import s3fs

s3 = s3fs.S3FileSystem()
counts = pd.read_csv(
  "s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/counts/counts_matrix.tsv",
  sep="\t",
  storage_options={"anon": False}
)
```

**Batch Download:**
```bash
# Download all counts matrices
aws s3 cp s3://dremel-lab-bucket/_HTS/HAROLD/exp_A_batch1/counts/ . --recursive --include "*.tsv"
```

---

## Best Practices

1. **Use meaningful `s3_sample_set_name`:** Include experiment ID, date, batch number (e.g., `coinfection_2024-05-12_batch1`)
2. **Enable S3 for production runs only:** Set `push_to_s3: false` for test/debugging runs to avoid cluttering S3 and incurring unnecessary costs
3. **Verify dry-run before large uploads:** Use `--dry-run` flag to preview transfer scope
4. **Tag objects for cost allocation:** Use S3 object tags (lab, project, pi) for AWS cost allocation
5. **Implement lifecycle policies:** Auto-transition GLACIER_IR → DEEP_ARCHIVE after 6 months (further cost reduction)
6. **Monitor S3 access logs:** Enable CloudTrail logging for security and compliance

---

## See Also

- [Usage Guide](usage.md) — S3 transfer as final pipeline step
- [Prerequisites](prereq.md) — AWS credential setup on Rivanna
- [Outputs](outputs.md) — Detailed description of transferred files
