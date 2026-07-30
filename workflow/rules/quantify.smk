
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
        # (set-resources.rseqc_fpkm.runtime in the profile, e.g.
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
        mkdir -p {params.tmpdir}
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


rule normalized_counts:
    input:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        html = join(RESULTSDIR,"counts","normalized_counts","{variant}","normalize.html")
    wildcard_constraints:
        variant = "|".join(VARIANTS.keys()) if VARIANTS else "NOVARIANT",
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
        
