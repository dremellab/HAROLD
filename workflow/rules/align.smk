rule star_align_two_pass:
    input:
        sa = join(STAR_INDEX_DIR, "SA"),
        fixed_gtf=join(REF_DIR, "ref.fixed.gtf"),
        R1 = rules.cutadapt.output.of1,
        R2 = rules.cutadapt.output.of2,
    output:
        bam = temp(join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.out.bam")),
        counts = join(RESULTSDIR, "{sample}", "STAR", "{sample}.ReadsPerGene.out.tab"),
        splice_junctions = join(RESULTSDIR, "{sample}", "STAR", "{sample}.SJ.out.tab"),
        transcript_sam = join(RESULTSDIR, "{sample}", "STAR", "Aligned.toTranscriptome.out.bam") if config.get("star_save_transcript_sam", False) else join(RESULTSDIR, "{sample}", "STAR", "{sample}.skip_transcript.out"),
    params:
        sample = "{sample}",
        star_index = STAR_INDEX_DIR,
        tmpdir=f"{TEMPDIR}/{str(uuid.uuid4())}",
        flanksize = config.get("star_flanksize", 15),
        alignTranscriptsPerReadNmax = config.get("star_alignTranscriptsPerReadNmax", 30000),
        out_prefix = join(RESULTSDIR, "{sample}", "STAR", "{sample}."),
        peorse = get_peorse,
        quantMode = "TranscriptomeSAM GeneCounts" if config.get("star_save_transcript_sam", False) else "GeneCounts",
    threads: getthreads("star_align_two_pass")
    container: config['containers']['star']
    shell:
        r"""
        set -exo pipefail
        if [[ "{params.peorse}" == "PE" ]]; then
            reads="{input.R1} {input.R2}"
        else
            reads="{input.R1}"
        fi
        STAR \
            --genomeDir {params.star_index} \
            --readFilesIn ${{reads}} \
            --readFilesCommand zcat \
            --runThreadN {threads} \
            --sjdbGTFfile {input.fixed_gtf} \
            --twopassMode Basic \
            --outFileNamePrefix {params.out_prefix} \
            --outTmpDir {params.tmpdir} \
            --outSAMtype BAM Unsorted \
            --quantMode {params.quantMode} \
            --outFilterMultimapNmax 20 \
            --outSJfilterOverhangMin 15 15 15 15 \
            --alignSJoverhangMin 15 \
            --alignSJDBoverhangMin 15 \
            --outFilterScoreMin 1 \
            --outFilterMatchNmin 1 \
            --outFilterMismatchNmax 2 \
            --outFilterMismatchNoverLmax 0.3 \
            --alignIntronMin 20 \
            --alignIntronMax 1000000 \
            --alignMatesGapMax 1000000 \
            --chimSegmentMin 15 \
            --chimScoreMin 15 \
            --chimJunctionOverhangMin {params.flanksize} \
            --chimScoreJunctionNonGTAG 0 \
            --chimMultimapNmax 10 \
            --chimOutType Junctions WithinBAM SoftClip \
            --alignTranscriptsPerReadNmax {params.alignTranscriptsPerReadNmax} \
            --alignEndsProtrude 10 ConcordantPair \
            --outFilterIntronMotifs None \
            --outSAMstrandField intronMotif
        outdir=$(dirname {output.bam})
        ls -alrth $outdir
        if [ ! -f "{output.transcript_sam}" ]; then
            touch "{output.transcript_sam}"
        fi

        """

rule sort_star:
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.out.bam"),
    output:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
        bai = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam.bai"),
        flagstat = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam.flagstat"),
        stats = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam.stats"),
        idxstats = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam.idxstats")
    threads: getthreads("sort_star")
    container: config['containers']['samtools']
    shell:
        r"""
        set -exo pipefail
        samtools sort -@ {threads} -o {output.bam} {input.bam}
        samtools index -@ {threads} {output.bam}
        samtools flagstat -@ {threads} {output.bam} > {output.bam}.flagstat
        samtools stats -@ {threads} {output.bam} > {output.bam}.stats
        samtools idxstats -@ {threads} {output.bam} > {output.bam}.idxstats
        """
