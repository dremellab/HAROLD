rule qualimap:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
    output:
        html = join(RESULTSDIR, "{sample}", "qualimap", "qualimapReport.html"),
        pdf = join(RESULTSDIR, "{sample}", "qualimap", "report.pdf"),
    params:
        sample = "{sample}",
        outdir = join(RESULTSDIR, "{sample}", "qualimap"),
    threads: getthreads("qualimap")
    container: config['containers']['qualimap']
    shell:
        r"""
        set -exo pipefail
        export JAVA_TOOL_OPTIONS="-Djava.awt.headless=true"
        qualimap --java-mem-size=4G bamqc \
            -bam {input.bam} \
            -outdir {params.outdir} \
            -outformat PDF:HTML \
            -nt {threads}
        """

localrules: gtf2genepred
rule gtf2genepred:
    input:
        gtf = join(REF_DIR, "ref.fixed.gtf"),
    output:
        genepred = join(REF_DIR, "ref.genes.genepred"),
    container: config['containers']['gtfToGenePred']
    shell:
        r"""
        set -exo pipefail
        gtfToGenePred {input.gtf} {output.genepred}
        """

localrules: genepred2bed12
rule genepred2bed12:
    input:
        genepred = join(REF_DIR, "ref.genes.genepred"),
    output:
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    params:
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    container: config['containers']['genePredToBed']
    shell:
        r"""
        set -exo pipefail
        genePredToBed {input.genepred} {output.bed12}
        """

rule rseqc_read_distribution:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        read_distribution = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.read_distribution.txt"),
    params:
        sample = "{sample}",
    container:
        config['containers']['rseqc'],
    threads: 1
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.read_distribution})
        mkdir -p $outdir
        cd $outdir
        read_distribution.py \
            -i {input.bam} \
            -r {input.bed12} \
            > {output.read_distribution}
        ls -alrth $outdir
        """

rule rseqc_tin:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        tin = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.summary.txt"),
    params:
        sample = "{sample}",
    container:
        config['containers']['rseqc'],
    threads: 1
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.tin})
        mkdir -p $outdir
        cd $outdir
        tin.py \
            -i {input.bam} \
            -r {input.bed12}
        ls -larth $outdir
        """

rule rseqc_geneBody_coverage:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        geneBody_coverage = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.geneBodyCoverage.txt"),
    params:
        sample = "{sample}",
    container:
        config['containers']['rseqc'],
    threads: 1
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.geneBody_coverage})
        mkdir -p $outdir
        cd $outdir
        geneBody_coverage.py \
            -i {input.bam} \
            -r {input.bed12} \
            -o ${{outdir}}/{params.sample}
        ls -larth $outdir
        """

localrules: multiqc
rule multiqc:
    input:
        expand(join(RESULTSDIR, "{sample}", "qualimap", "qualimapReport.html")                              ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.read_distribution.txt")                      ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.strandedness.txt")                           ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.geneBodyCoverage.txt")                       ,sample=SAMPLES),  # times out with 8 hours as well .. commenting out for now
        expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.summary.txt")      ,sample=SAMPLES),
    output:
        multiqc = join(RESULTSDIR, "multiqc_report.html"),
    container:
        config['containers']['multiqc'],
    threads: 1
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.multiqc})
        multiqc --verbose --interactive --force .
        """
