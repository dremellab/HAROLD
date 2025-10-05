

rule kraken2:
    input:
        unpack(get_fastqs),
    output:
        kraken2_report = join(RESULTSDIR, "{sample}", "kraken2", "{sample}.kraken2.report.txt"),
    params:
        sample = "{sample}",
        outdir = join(RESULTSDIR, "{sample}", "kraken2"),
        kraken2_db = config['kraken2_db'],
        kraken2_params = config['kraken2_params'],
        peorse=get_peorse,
    threads: _get_threads("kraken2", profile_config)
    container: config['containers']['kraken2']
    shell:
        r"""
        set -exo pipefail
        mkdir -p {params.outdir}

        if [ "{params.peorse}" == "PE" ]; then
            kraken2 --db {params.kraken2_db} \
                --paired {input.R1} {input.R2} \
                {params.kraken2_params} \
                --report {output.kraken2_report} \
                --threads {threads}
        else
            kraken2 --db {params.kraken2_db} \
                {input.R1} \
                {params.kraken2_params} \
                --report {output.kraken2_report} \
                --threads {threads}
        fi
        """

rule qualimap:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
    output:
        html = join(RESULTSDIR, "{sample}", "qualimap", "qualimapReport.html"),
        pdf = join(RESULTSDIR, "{sample}", "qualimap", "report.pdf"),
    params:
        sample = "{sample}",
        outdir = join(RESULTSDIR, "{sample}", "qualimap"),
    threads: _get_threads("qualimap", profile_config)
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
        gtfToGenePred -ignoreGroupsWithoutExons {input.gtf} {output.genepred}
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
    threads: _get_threads("rseqc_read_distribution", profile_config)
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
        xls = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.tin.xls"),
    params:
        sample = "{sample}",
    container:
        config['containers']['rseqc'],
    threads: _get_threads("rseqc_tin", profile_config)
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

rule aggregate_tin:
    input:
        expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.tin.xls"), sample=SAMPLES),
    output:
        agg_tin = join(RESULTSDIR, "counts", "aggregate_tin.tsv"),
    params:
        script = join(SCRIPTS_DIR, "_aggregate_tin.py"),
    container: config['containers']['star_ucsc_cufflinks']
    shell:
        r"""
        set -exo pipefail
        mkdir -p $(dirname {output.agg_tin})
        cd $(dirname {output.agg_tin})
        python {params.script} {input} > {output.agg_tin}
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
    threads: _get_threads("rseqc_geneBody_coverage", profile_config)
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

rule rseqc_read_gc:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.{regionname}.bam"),
    output:
        read_gc = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.{regionname}.GC.xls"),
    params:
        sample = "{sample}",
        regionname = "{regionname}",
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    container:
        config['containers']['rseqc'],
    threads: _get_threads("rseqc_read_gc", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.read_gc})
        mkdir -p $outdir
        mkdir -p {params.tmpdir}
        cd $outdir
        read_GC.py \
            -i {input.bam} \
            -o ${{outdir}}/{params.sample}.{params.regionname}
        ls -larth $outdir
        """

rule rseqc_junction_annotation:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.{regionname}.bam"),
        bed12 = join(REF_DIR, "ref.genes.bed12"),
    output:
        junctions = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.{regionname}.junction.bed"),
    params:
        sample = "{sample}",
        regionname = "{regionname}",
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    container:
        config['containers']['rseqc'],
    threads: _get_threads("rseqc_junction_annotation", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.junctions})
        mkdir -p $outdir
        mkdir -p {params.tmpdir}
        cd $outdir
        junction_annotation.py \
            -i {input.bam} \
            -r {input.bed12} \
            -o ${{outdir}}/{params.sample}.{params.regionname} | tee {params.sample}.{params.regionname}.junction.bed.log
        if grep -q "total = 0" {params.sample}.{params.regionname}.junction.bed.log; then
            touch {output.junctions}
        fi
        ls -larth $outdir
        """

rule junctions_to_bigbed:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.{regionname}.bam"),
        junctions = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.{regionname}.junction.bed"),
    output:
        bb = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.{regionname}.junction.bb"),
    params:
        sample = "{sample}",
        regionname = "{regionname}",
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
    container:
        config['containers']['bedToBigBed'],
    threads: _get_threads("junctions_to_bigbed", profile_config)
    shell:
        r"""
        set -exo pipefail
        # if no junctions, create empty bigbed file
        if [ ! -s "{input.junctions}" ]; then
            touch "{output.bb}"
            exit 0
        fi
        outdir=$(dirname "{output.bb}")
        mkdir -p "$outdir"
        mkdir -p "{params.tmpdir}"
        cd $outdir
        samtools view -H {input.bam} \
          | awk '$1=="@SQ"{{split($2,a,":"); split($3,b,":"); print a[2]"\t"b[2]}}' \
          > {params.tmpdir}/genome.sizes
        bedSort "{input.junctions}" "{params.tmpdir}/junctions.sorted.bed"
        # bigBed score can only be 0-1000, so cap it at 1000
        max=$(awk 'BEGIN{{max=0}} $5>max{{max=$5}} END{{print max}}'  "{params.tmpdir}/junctions.sorted.bed")
        awk -v max="$max" 'BEGIN{{OFS="\t"}} {{$5=int(($5/max)*1000); print}}' "{params.tmpdir}/junctions.sorted.bed" > "{params.tmpdir}/junctions.sorted.rescaled.bed"
        bedToBigBed "{params.tmpdir}/junctions.sorted.rescaled.bed" "{params.tmpdir}/genome.sizes" "{output.bb}"
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
        expand(join(RESULTSDIR, "{sample}", "kraken2", "{sample}.kraken2.report.txt")                       ,sample=SAMPLES),
    output:
        multiqc = join(RESULTSDIR, "multiqc_report.html"),
    container:
        config['containers']['multiqc'],
    threads: 1
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.multiqc})
        cd $outdir
        multiqc --verbose --interactive --force .
        """
