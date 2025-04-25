
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
        strandedness_txt = expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.strandedness.txt"), sample=SAMPLES)
    output:
        counts = join(RESULTSDIR,"counts","counts_matrix.tsv"),
        strand = join(RESULTSDIR,"counts","sample_strandedness.tsv")
    params:
        script = join(SCRIPTS_DIR,"_aggregate_counts_by_strandedness.py"),
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    run:
        # Extract STAR directory paths from strandedness files
        sample_dirs = sorted(set(os.path.dirname(path) for path in input.strandedness_txt))
        print("Sample strandedness dirs:", sample_dirs)
        sample_dir_file = join(params.tmpdir, "sample_dirs.txt")
        os.makedirs(os.path.dirname(sample_dir_file), exist_ok=True)
        with open(sample_dir_file, "w") as f:
            for d in sample_dirs:
                f.write(d + "\n")
        os.makedirs(os.path.dirname(output.counts), exist_ok=True)
        shell(f"python {params.script} {sample_dir_file} {output.counts} {output.strand}")
