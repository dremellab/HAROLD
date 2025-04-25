
rule split_bam:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
    output:
        bams = expand(join(RESULTSDIR, "{{sample}}", "STAR", "{{sample}}.{regionname}.bam"), regionname=HOST_VIRUSES),
    params:
        sample = "{sample}",
        outdir = join(RESULTSDIR, "{sample}", "STAR"),
        regions = REF_REGIONS_HOST_VIRUSES,
    threads:
        getthreads("split_bam")
    container:
        config['containers']['samtools']
    shell:
        r"""
        set -exo pipefail
        while read regionname regions; do
            outbam={params.outdir}/{params.sample}.${{regionname}}.bam

            samtools view -@ {threads} -b {input.bam} ${{regions}} > ${{outbam}}
            samtools index -@ {threads} ${{outbam}}
            samtools flagstat -@ {threads} ${{outbam}} > ${{outbam}}.flagstat
            samtools stats -@ {threads} ${{outbam}} > ${{outbam}}.stats
            samtools idxstats -@ {threads} ${{outbam}} > ${{outbam}}.idxstats
        done < {params.regions}
        """


rule bam_to_bigwig:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.{regionname}.bam"),
    output:
        bw = join(RESULTSDIR, "{sample}", "bigwigs", "{sample}.{regionname}.bw"),
    params:
        sample = "{sample}",
        regionname = "{regionname}",
        normalize = config.get("deeptools_normalize", "RPKM"),
        binSize = config.get("deeptools_binSize", 10),
        effectiveGenomeSizes = EGS,
    threads:
        getthreads("bam_to_bigwig")
    container:
        config['containers']['deeptools']
    shell:
        r"""
        set -exo pipefail
        mkdir -p $(dirname {output.bw})
        bamCoverage \
            --bam {input.bam} \
            --outFileName {output.bw} \
            --outFileFormat bigwig \
            --binSize {params.binSize} \
            --normalizeUsing {params.normalize} \
            --numberOfProcessors {threads}
        """
