
rule split_bam:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
    output:
        bams = expand(join(RESULTSDIR, "{{sample}}", "STAR", "{{sample}}.{regionname}.bam"), regionname=HOST_VIRUSES),
    params:
        sample = "{sample}",
        outdir = join(RESULTSDIR, "{sample}", "STAR"),
        regions = REF_REGIONS_HOST_VIRUSES,
        tmpdir = f"{TEMPDIR}/{str(uuid.uuid4())}",
    threads:
        _get_threads("split_bam", profile_config)
    container:
        config['containers']['samtools']
    shell:
        r"""
        set -exo pipefail
        mkdir -p {params.tmpdir}
        while read regionname regions; do
            outbam={params.outdir}/{params.sample}.${{regionname}}.bam
            tmpbam={params.tmpdir}/{params.sample}.${{regionname}}.bam

            samtools view -@ {threads} -b {input.bam} ${{regions}} > ${{tmpbam}}
            samtools index -@ {threads} ${{tmpbam}}
            samtools flagstat -@ {threads} ${{tmpbam}} > ${{tmpbam}}.flagstat
            samtools stats -@ {threads} ${{tmpbam}} > ${{tmpbam}}.stats
            samtools idxstats -@ {threads} ${{tmpbam}} > ${{tmpbam}}.idxstats

            mv -f ${{tmpbam}} ${{outbam}}
            mv -f ${{tmpbam}}.bai ${{outbam}}.bai
            mv -f ${{tmpbam}}.flagstat ${{outbam}}.flagstat
            mv -f ${{tmpbam}}.stats ${{outbam}}.stats
            mv -f ${{tmpbam}}.idxstats ${{outbam}}.idxstats
        done < {params.regions}
        rm -rf {params.tmpdir}
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
        _get_threads("bam_to_bigwig", profile_config)
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
