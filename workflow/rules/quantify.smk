
# infer_strandedness (RSeQC infer_experiment.py) and its gtf_to_bed input were replaced by
# rustqc_rna_combined (workflow/rules/qc.smk), which produces the same
# {sample}.strandedness.txt at the same path. gtf_to_bed's plain-BED output (ref.genes.bed) had
# no other consumer, so it was removed alongside infer_strandedness rather than left orphaned.

localrules: aggregate_stranded_counts
rule aggregate_stranded_counts:
    input:
        counts_files = expand(join(RESULTSDIR, "{sample}", "STAR", "{sample}.ReadsPerGene.out.tab"), sample=SAMPLES),
        strandedness_files = expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.strandedness.txt"), sample=SAMPLES),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        counts_rpkm = join(RESULTSDIR,"counts","counts_matrix.rpkm.tsv"),
        counts_tpm = join(RESULTSDIR,"counts","counts_matrix.tpm.tsv"),
        strand = join(RESULTSDIR,"counts","sample_strandedness.tsv")
    params:
        regions = REF_REGIONS,
        use_infer_strandedness = USE_INFER_STRANDEDNESS,
        infer_strandedness_fraction = INFER_FRACTION_THRESHOLD,
        manifest_file = MANIFEST_FILE,
        strandinfo_column = STRANDEDNESS_COLUMN,
        script1 = join(SCRIPTS_DIR,"_aggregate_counts_by_strandedness.py"),
        script2 = join(SCRIPTS_DIR,"_raw_counts_to_tpm.py")
    run:
        os.makedirs(os.path.dirname(output.counts), exist_ok=True)
        counts_list = ",".join(input.counts_files)
        strandedness_list = ",".join(input.strandedness_files)
        strand_arg = "--infer_strandedness" if params.use_infer_strandedness == "true" else "--no-infer_strandedness"
        shell(f"python {params.script1} --counts {counts_list} --strandinfo {strandedness_list} --output_counts {output.counts} --output_strand {output.strand} --gtf {input.gtf} --regions {params.regions} {strand_arg} --manifest_file {params.manifest_file} --strandinfo_column {params.strandinfo_column} --infer_strandedness_fraction {params.infer_strandedness_fraction}")
        shell(f"python {params.script2} --input {output.counts} --samples {params.manifest_file} --rpkm_output {output.counts_rpkm} --tpm_output {output.counts_tpm}")

rule rseqc_fpkm:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        strand = join(RESULTSDIR,"counts","sample_strandedness.tsv"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        fpkm = join(RESULTSDIR, "{sample}", "counts", "{sample}.rseqc_fpkm_tpm.tsv"),
    params:
        sample = "{sample}",
        tmpdir=lambda wildcards: join(TEMPDIR, "rseqc_fpkm", wildcards.sample, str(uuid.uuid4())),
        peorse = get_peorse,
        script1 = join(SCRIPTS_DIR, "_get_strand.py"),
        script2 = join(SCRIPTS_DIR, "_rseqc_fpkm_add_tpm.py"),
    container:
        config['containers']['rseqc']
    threads: _get_threads("rseqc_fpkm", profile_config)
    resources:
        # FPKM_count.py's runtime scales with transcript count (observed:
        # ~230k+ transcripts still unfinished at the 4h default on a full
        # hg38 annotation), so a single static cap either wastes allocation
        # on small references or isn't enough on large ones. `attempt` is
        # bumped by Snakemake on every restart (restart-times: 3, set in
        # the profile config), so this scales the per-rule base runtime
        # (retry-base-resources.rseqc_fpkm.runtime in the profile, e.g.
        # config/rivanna/config.yaml) up on each retry instead of failing
        # identically on every attempt.
        runtime=lambda wildcards, attempt: _get_runtime("rseqc_fpkm", profile_config) * attempt,
    shell:
        r"""
        set -exo pipefail

        outdir=$(dirname {output.fpkm})
        mkdir -p "$outdir"
        cd "$outdir"

        # Temporary directory and prefix
        tmpdir_parent=$(dirname "{params.tmpdir}")
        mkdir -p "$tmpdir_parent"
        test -w "$tmpdir_parent" || {{ echo "rseqc_fpkm tempdir parent not writable: $tmpdir_parent" >&2; exit 1; }}
        rm -rf "{params.tmpdir}"
        mkdir -p "{params.tmpdir}"
        trap 'rm -rf "{params.tmpdir}"' EXIT
        prefix="{params.tmpdir}/{params.sample}"

        # Get strand rule
        strand=$(python {params.script1} --input {input.strand} --sample {params.sample} --peorse {params.peorse})

        if [[ "$strand" == "none" ]]; then
            strandstr=""
        else
            strandstr="-d \"$strand\""
        fi

        # Run RSeQC FPKM_count
        FPKM_count.py \
            -i {input.bam} \
            -r {input.bed12} \
            -o "$prefix" \
            $strandstr \
            --only-exonic \
            -q 30

        # Add TPM
        python {params.script2} "${{prefix}}.FPKM.xls" "{output.fpkm}"

        # Clean up
        rm -rf {params.tmpdir}
        """


localrules: aggregate_transcript_level_counts
rule aggregate_transcript_level_counts:
    input:
        counts_files = expand(join(RESULTSDIR, "{sample}", "counts", "{sample}.rseqc_fpkm_tpm.tsv"), sample=SAMPLES),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        counts = join(RESULTSDIR,"counts","counts_matrix.transcript_level.tsv"),
        counts_fpkm = join(RESULTSDIR,"counts","counts_matrix.transcript_level.rpkm.tsv"),
        counts_tpm = join(RESULTSDIR,"counts","counts_matrix.transcript_level.tpm.tsv"),
    params:
        manifest_file = MANIFEST_FILE,
        script1 = join(SCRIPTS_DIR,"_aggregate_transcript_level_counts.py")
    run:
        os.makedirs(os.path.dirname(output.counts), exist_ok=True)
        shell(f"python {params.script1} --input {input.counts_files} --gtf {input.gtf} --fragcount_output {output.counts} --fpkm_output {output.counts_fpkm} --tpm_output {output.counts_tpm}")


# diffex normalize writes its normalized-count matrices (limma/edgeR/DESeq2, ERCC-scaled
# when --use-ercc is set) as flat TSVs next to normalize.html. Which extra files show up is
# independent per axis: the batch-corrected limma file only exists for w_batch variants, and
# the ERCC_corrected_{log2_,}counts.tsv precursor files (DiffEx >= 0.5.7, dremellab/DiffEx#44)
# only exist for w_ercc variants. Snakemake output paths can't be conditional on a wildcard's
# value within one rule, so all four ercc x batch combinations are split into their own rule
# with a matching wildcard_constraints, rather than one rule with a variable output list.
rule normalized_counts_wo_ercc_wo_batch:
    input:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        html = join(RESULTSDIR,"counts","normalized_counts","{variant}","normalize.html"),
        limma_voom = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_voom_normalized_counts.tsv"),
        edger_tmm_logcpm = join(RESULTSDIR,"counts","normalized_counts","{variant}","edgeR_TMM_normalized_logCPM_counts.tsv"),
        deseq2_vst = join(RESULTSDIR,"counts","normalized_counts","{variant}","DESeq2_vst_normalized_counts.tsv"),
    wildcard_constraints:
        variant = "|".join(v for v in VARIANTS if not VARIANTS[v][0] and not VARIANTS[v][1]) or "NOVARIANT",
    params:
        manifest_file = MANIFEST_FILE,
        user_ercc = lambda wc: VARIANTS[wc.variant][0],
        user_batch = lambda wc: VARIANTS[wc.variant][1],
        ercc_mix = str(config.get('diffex', {}).get('ercc_mix', '1')).lower(),
        batch_column = str(config.get('diffex', {}).get('batch_column', 'batch')),
        genes_selection = str(config.get('diffex', {}).get('genes_selection', 'both')).lower(),
        host = DIFFEX_HOST,
    container:
        config['containers']['diffex']
    threads: _get_threads("diffex_normalized_counts", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.html})
        mkdir -p $outdir
        if [ "{params.user_ercc}" = "True" ]; then
            ercc_arg="--use-ercc --ercc-mix {params.ercc_mix}"
        else
            ercc_arg=""
        fi
        if [ "{params.user_batch}" = "True" ]; then
            batch_arg="--use-batch --batch-column {params.batch_column}"
        else
            batch_arg=""
        fi
        cd /app/DiffEx
        diffex normalize \
            -c {input.counts} \
            -s {params.manifest_file} \
            $ercc_arg \
            --sample-column sampleName \
            --group-column groupName \
            $batch_arg \
            -o $outdir \
            --host {params.host} \
            --genes-selection {params.genes_selection}
        ls -alrth $outdir
        """

rule normalized_counts_wo_ercc_w_batch:
    input:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        html = join(RESULTSDIR,"counts","normalized_counts","{variant}","normalize.html"),
        limma_voom = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_voom_normalized_counts.tsv"),
        limma_voom_batch_corrected = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_voom_normalized_counts_batch_corrected.tsv"),
        edger_tmm_logcpm = join(RESULTSDIR,"counts","normalized_counts","{variant}","edgeR_TMM_normalized_logCPM_counts.tsv"),
        deseq2_vst = join(RESULTSDIR,"counts","normalized_counts","{variant}","DESeq2_vst_normalized_counts.tsv"),
    wildcard_constraints:
        variant = "|".join(v for v in VARIANTS if not VARIANTS[v][0] and VARIANTS[v][1]) or "NOVARIANT",
    params:
        manifest_file = MANIFEST_FILE,
        user_ercc = lambda wc: VARIANTS[wc.variant][0],
        user_batch = lambda wc: VARIANTS[wc.variant][1],
        ercc_mix = str(config.get('diffex', {}).get('ercc_mix', '1')).lower(),
        batch_column = str(config.get('diffex', {}).get('batch_column', 'batch')),
        genes_selection = str(config.get('diffex', {}).get('genes_selection', 'both')).lower(),
        host = DIFFEX_HOST,
    container:
        config['containers']['diffex']
    threads: _get_threads("diffex_normalized_counts", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.html})
        mkdir -p $outdir
        if [ "{params.user_ercc}" = "True" ]; then
            ercc_arg="--use-ercc --ercc-mix {params.ercc_mix}"
        else
            ercc_arg=""
        fi
        if [ "{params.user_batch}" = "True" ]; then
            batch_arg="--use-batch --batch-column {params.batch_column}"
        else
            batch_arg=""
        fi
        cd /app/DiffEx
        diffex normalize \
            -c {input.counts} \
            -s {params.manifest_file} \
            $ercc_arg \
            --sample-column sampleName \
            --group-column groupName \
            $batch_arg \
            -o $outdir \
            --host {params.host} \
            --genes-selection {params.genes_selection}
        ls -alrth $outdir
        """

rule normalized_counts_w_ercc_wo_batch:
    input:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        html = join(RESULTSDIR,"counts","normalized_counts","{variant}","normalize.html"),
        limma_rpkm = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_pseudo_rpkm_counts.tsv"),
        limma_log2_rpkm = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_log2normalized_pseudo_rpkm_counts.tsv"),
        edger_tmm_logcpm = join(RESULTSDIR,"counts","normalized_counts","{variant}","edgeR_TMM_normalized_logCPM_counts.tsv"),
        deseq2_vst = join(RESULTSDIR,"counts","normalized_counts","{variant}","DESeq2_vst_normalized_counts.tsv"),
        ercc_corrected_log2 = join(RESULTSDIR,"counts","normalized_counts","{variant}","ERCC_corrected_log2_counts.tsv"),
        ercc_corrected_linear = join(RESULTSDIR,"counts","normalized_counts","{variant}","ERCC_corrected_counts.tsv"),
    wildcard_constraints:
        variant = "|".join(v for v in VARIANTS if VARIANTS[v][0] and not VARIANTS[v][1]) or "NOVARIANT",
    params:
        manifest_file = MANIFEST_FILE,
        user_ercc = lambda wc: VARIANTS[wc.variant][0],
        user_batch = lambda wc: VARIANTS[wc.variant][1],
        ercc_mix = str(config.get('diffex', {}).get('ercc_mix', '1')).lower(),
        batch_column = str(config.get('diffex', {}).get('batch_column', 'batch')),
        genes_selection = str(config.get('diffex', {}).get('genes_selection', 'both')).lower(),
        host = DIFFEX_HOST,
    container:
        config['containers']['diffex']
    threads: _get_threads("diffex_normalized_counts", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.html})
        mkdir -p $outdir
        if [ "{params.user_ercc}" = "True" ]; then
            ercc_arg="--use-ercc --ercc-mix {params.ercc_mix}"
        else
            ercc_arg=""
        fi
        if [ "{params.user_batch}" = "True" ]; then
            batch_arg="--use-batch --batch-column {params.batch_column}"
        else
            batch_arg=""
        fi
        cd /app/DiffEx
        diffex normalize \
            -c {input.counts} \
            -s {params.manifest_file} \
            $ercc_arg \
            --sample-column sampleName \
            --group-column groupName \
            $batch_arg \
            -o $outdir \
            --host {params.host} \
            --genes-selection {params.genes_selection}
        ls -alrth $outdir
        """

rule normalized_counts_w_ercc_w_batch:
    input:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        html = join(RESULTSDIR,"counts","normalized_counts","{variant}","normalize.html"),
        limma_rpkm = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_pseudo_rpkm_counts.tsv"),
        limma_log2_rpkm = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_log2normalized_pseudo_rpkm_counts.tsv"),
        limma_log2_rpkm_batch_corrected = join(RESULTSDIR,"counts","normalized_counts","{variant}","limma_log2normalized_pseudo_rpkm_counts_batch_corrected.tsv"),
        edger_tmm_logcpm = join(RESULTSDIR,"counts","normalized_counts","{variant}","edgeR_TMM_normalized_logCPM_counts.tsv"),
        deseq2_vst = join(RESULTSDIR,"counts","normalized_counts","{variant}","DESeq2_vst_normalized_counts.tsv"),
        ercc_corrected_log2 = join(RESULTSDIR,"counts","normalized_counts","{variant}","ERCC_corrected_log2_counts.tsv"),
        ercc_corrected_linear = join(RESULTSDIR,"counts","normalized_counts","{variant}","ERCC_corrected_counts.tsv"),
    wildcard_constraints:
        variant = "|".join(v for v in VARIANTS if VARIANTS[v][0] and VARIANTS[v][1]) or "NOVARIANT",
    params:
        manifest_file = MANIFEST_FILE,
        user_ercc = lambda wc: VARIANTS[wc.variant][0],
        user_batch = lambda wc: VARIANTS[wc.variant][1],
        ercc_mix = str(config.get('diffex', {}).get('ercc_mix', '1')).lower(),
        batch_column = str(config.get('diffex', {}).get('batch_column', 'batch')),
        genes_selection = str(config.get('diffex', {}).get('genes_selection', 'both')).lower(),
        host = DIFFEX_HOST,
    container:
        config['containers']['diffex']
    threads: _get_threads("diffex_normalized_counts", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.html})
        mkdir -p $outdir
        if [ "{params.user_ercc}" = "True" ]; then
            ercc_arg="--use-ercc --ercc-mix {params.ercc_mix}"
        else
            ercc_arg=""
        fi
        if [ "{params.user_batch}" = "True" ]; then
            batch_arg="--use-batch --batch-column {params.batch_column}"
        else
            batch_arg=""
        fi
        cd /app/DiffEx
        diffex normalize \
            -c {input.counts} \
            -s {params.manifest_file} \
            $ercc_arg \
            --sample-column sampleName \
            --group-column groupName \
            $batch_arg \
            -o $outdir \
            --host {params.host} \
            --genes-selection {params.genes_selection}
        ls -alrth $outdir
        """



# CDS-level counts with featureCounts, for translation-efficiency (TE) calculations against
# RIBOLD's Ribo-seq CDS counts (ribold_cds_counts.tsv). Settings mirror RIBOLD's `counting:`
# block (-t CDS -g gene_id, multi-mapped reads not counted), and the matrix has the same
# gene_id + one-column-per-sample layout, so the two can be joined on gene_id. This is separate
# from, and does not replace, the STAR ReadsPerGene matrix (counts_matrix.tsv) used for DEG.
# Defined only when enabled so configs without `containers.featurecounts` still parse.
if FEATURECOUNTS_CDS == "true":

    # Additive/viral GTFs have exon rows but no CDS rows; copy each exon as a CDS row (same
    # convention as RIBOLD) so those genes are present in the CDS matrix too. Kept as its own
    # GTF so nothing else that reads ref.fixed.gtf (STAR, rustqc, qualimap) sees the extra rows.
    localrules: build_cds_gtf
    rule build_cds_gtf:
        input:
            gtf = join(REF_DIR, "ref.fixed.gtf"),
        output:
            gtf = join(REF_DIR, "ref.cds.gtf"),
        params:
            regions = REF_REGIONS,
            host = HOST,
            script = join(SCRIPTS_DIR, "_build_cds_gtf.py"),
        shell:
            r"""
            set -exo pipefail
            python {params.script} --ingtf {input.gtf} --regions {params.regions} --host "{params.host}" --outgtf {output.gtf}
            """

    rule featurecounts_cds:
        input:
            bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
            strand = join(RESULTSDIR, "counts", "sample_strandedness.tsv"),
            gtf = join(REF_DIR, "ref.cds.gtf"),
        output:
            counts = join(RESULTSDIR, "{sample}", "counts", "{sample}.cds.featureCounts.tsv"),
            # not named *.summary on purpose: MultiQC runs over all of results/ and would
            # otherwise load this next to rustqc's featureCounts summary under the same
            # sample name
            summary = join(RESULTSDIR, "{sample}", "counts", "{sample}.cds.featureCounts.summary.tsv"),
        params:
            sample = "{sample}",
            tmpdir = lambda wildcards: join(TEMPDIR, "featurecounts_cds", wildcards.sample, str(uuid.uuid4())),
            peorse = get_peorse,
            feature_type = config.get("featurecounts_cds", {}).get("feature_type", "CDS"),
            attribute_type = config.get("featurecounts_cds", {}).get("attribute_type", "gene_id"),
            extra_args = config.get("featurecounts_cds", {}).get("extra_args", ""),
        container:
            config['containers']['featurecounts']
        threads: _get_threads("featurecounts_cds", profile_config)
        shell:
            r"""
            set -exo pipefail

            mkdir -p $(dirname {output.counts})

            # Temporary directory (featureCounts re-sorts paired-end BAMs by name in --tmpDir)
            tmpdir_parent=$(dirname "{params.tmpdir}")
            mkdir -p "$tmpdir_parent"
            test -w "$tmpdir_parent" || {{ echo "featurecounts_cds tempdir parent not writable: $tmpdir_parent" >&2; exit 1; }}
            rm -rf "{params.tmpdir}"
            mkdir -p "{params.tmpdir}"
            trap 'rm -rf "{params.tmpdir}"' EXIT

            # used_strand (3rd column of sample_strandedness.tsv) -> featureCounts -s; same
            # per-sample call that picks the STAR ReadsPerGene column for counts_matrix.tsv
            used_strand=$(awk -F'\t' -v s="{params.sample}" 'NR>1 && $1==s {{print $3}}' {input.strand})
            case "$used_strand" in
                unstranded) strand=0 ;;
                forward)    strand=1 ;;
                reverse)    strand=2 ;;
                *) echo "Unknown used_strand '$used_strand' for sample {params.sample} in {input.strand}" >&2; exit 1 ;;
            esac

            # paired-end: count fragments, not reads
            if [[ "{params.peorse}" == "PE" ]]; then
                pestr="-p --countReadPairs"
            else
                pestr=""
            fi

            featureCounts \
                -T {threads} \
                -t {params.feature_type} \
                -g {params.attribute_type} \
                -s $strand \
                $pestr \
                {params.extra_args} \
                --tmpDir "{params.tmpdir}" \
                -a {input.gtf} \
                -o "{params.tmpdir}/{params.sample}.txt" \
                {input.bam}

            cp "{params.tmpdir}/{params.sample}.txt" {output.counts}
            cp "{params.tmpdir}/{params.sample}.txt.summary" {output.summary}
            """

    localrules: aggregate_cds_counts
    rule aggregate_cds_counts:
        input:
            counts_files = expand(join(RESULTSDIR, "{sample}", "counts", "{sample}.cds.featureCounts.tsv"), sample=SAMPLES),
            summary_files = expand(join(RESULTSDIR, "{sample}", "counts", "{sample}.cds.featureCounts.summary.tsv"), sample=SAMPLES),
        output:
            counts = join(RESULTSDIR, "counts", "cds_counts_matrix.tsv"),
            summary = join(RESULTSDIR, "counts", "cds_counts_matrix.featureCounts_summary.tsv"),
        params:
            samples = ",".join(SAMPLES),
            script = join(SCRIPTS_DIR, "_aggregate_cds_counts.py"),
        run:
            os.makedirs(os.path.dirname(output.counts), exist_ok=True)
            counts_list = ",".join(input.counts_files)
            summary_list = ",".join(input.summary_files)
            shell(f"python {params.script} --samples {params.samples} --counts {counts_list} --summaries {summary_list} --output_counts {output.counts} --output_summary {output.summary}")
