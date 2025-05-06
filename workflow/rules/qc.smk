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
        read_distribution.py \
            -i {input.bam} \
            -r {input.bed12} \
            > {output.read_distribution}
        """

rule rseqc_tin:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        tin = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.tin.txt"),
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
        tin.py \
            -i {input.bam} \
            -r {input.bed12} \
            > {output.tin}
        """

rule rseqc_geneBody_coverage:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        geneBody_coverage = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.geneBody_coverage.txt"),
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
        geneBody_coverage.py \
            -i {input.bam} \
            -r {input.bed12} \
            -o {output.geneBody_coverage}
        """
