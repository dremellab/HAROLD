
localrules: gtf_to_bed
rule gtf_to_bed:
    input:
        gtf = join(REF_DIR, "ref.fixed.gtf"),
    output:
        bed = join(REF_DIR, "ref.genes.bed"),
    params:
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    container:
        config['containers']['gffread']
    shell:
        r"""
        set -exo pipefail
        mkdir -p {params.tmpdir}
        outdir=$(dirname {output.bed})
        gffread {input.gtf} -T -o {params.tmpdir}/temp.gtf
        awk '$3 == "exon" {{
            gsub(/[";]/, "", $10);
            print $1"\t"($4-1)"\t"$5"\t"$10"\t0\t"$7
        }}' {params.tmpdir}/temp.gtf > {output.bed}
        """

rule infer_strandedness:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bed = join(REF_DIR, "ref.genes.bed"),
    output:
        strandedness = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.strandedness.txt"),
    params:
        sample = "{sample}",
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    container:
        config['containers']['rseqc']
    threads: _get_threads("rseqc_infer_strandedness", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.strandedness})
        mkdir -p $outdir
        mkdir -p {params.tmpdir}
        infer_experiment.py \
            -i {input.bam} \
            -r {input.bed} \
            > {output.strandedness}
        """

localrules: aggregate_stranded_counts
rule aggregate_stranded_counts:
    input:
        counts_files = expand(join(RESULTSDIR, "{sample}", "STAR", "{sample}.ReadsPerGene.out.tab"), sample=SAMPLES),
        strandedness_files = expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.strandedness.txt"), sample=SAMPLES),
        gtf = join(REF_DIR, "ref.fixed.gtf")
    output:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        strand = join(RESULTSDIR,"counts","sample_strandedness.tsv")
    params:
        regions = REF_REGIONS,
        infer_strandedness = INFER_STRANDEDNESS,
        infer_strandedness_fraction = INFER_FRACTION_THRESHOLD,
        manifest_file = MANIFEST_FILE,
        strandinfo_column = STRANDEDNESS_COLUMN,
        script = join(SCRIPTS_DIR,"_aggregate_counts_by_strandedness.py")
    run:
        os.makedirs(os.path.dirname(output.counts), exist_ok=True)
        counts_list = ",".join(input.counts_files)
        strandedness_list = ",".join(input.strandedness_files)
        strand_arg = "--infer_strandedness" if params.infer_strandedness == "true" else "--no-infer_strandedness"
        shell(f"python {params.script} --counts {counts_list} --strandinfo {strandedness_list} --output_counts {output.counts} --output_strand {output.strand} --gtf {input.gtf} --regions {params.regions} {strand_arg} --manifest_file {params.manifest_file} --strandinfo_column {params.strandinfo_column} --infer_strandedness_fraction {params.infer_strandedness_fraction}")
