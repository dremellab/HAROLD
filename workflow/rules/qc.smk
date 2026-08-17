

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
                --output /dev/null \
                --threads {threads}
        else
            kraken2 --db {params.kraken2_db} \
                {input.R1} \
                {params.kraken2_params} \
                --report {output.kraken2_report} \
                --output /dev/null \
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
        java_mem_mb=$(( {resources.mem_mb} * 80 / 100 ))
        java_mem_g=$(( java_mem_mb / 1024 ))
        if [ "$java_mem_g" -lt 4 ]; then
            java_mem_g=4
        fi
        export JAVA_TOOL_OPTIONS="-Djava.awt.headless=true"
        qualimap --java-mem-size="${{java_mem_g}}G" bamqc \
            -bam {input.bam} \
            -outdir {params.outdir} \
            -outformat PDF:HTML \
            -nt {threads}
        """

rule mark_duplicates:
    # rustqc's dupRadar module requires duplicate-marked (not removed) alignments -- without this,
    # it silently reports 0% duplication for every gene (confirmed in validation testing), which is
    # misleading rather than merely uninformative. No dup-marking step exists anywhere else in HAROLD
    # today, so this is net new. Output is consumed only by rustqc_rna_combined/rustqc_rna_combined_probe;
    # every other consumer of the STAR bam (split_bam, sort_star's flagstat/stats/idxstats, STAR
    # GeneCounts, alignment_summary) keeps using the original, unmarked bam.
    input:
        bam = join(RESULTSDIR, "{sample}", "STAR", "{sample}.Aligned.sortedByCoord.out.bam"),
    output:
        bam = temp(join(TEMPDIR, "mark_duplicates", "{sample}", "{sample}.markdup.bam")),
        bai = temp(join(TEMPDIR, "mark_duplicates", "{sample}", "{sample}.markdup.bam.bai")),
        metrics = join(RESULTSDIR, "{sample}", "STAR", "{sample}.markdup_metrics.txt"),
    params:
        tmpdir = lambda wildcards: join(TEMPDIR, "mark_duplicates_tmp", wildcards.sample, str(uuid.uuid4())),
    container:
        config['containers']['picard'],
    threads: _get_threads("mark_duplicates", profile_config)
    resources:
        # No real memory data for this rule yet (see set-resources comment in
        # config/rivanna/config.yaml) -- double the base mem_mb on each retry so a
        # too-low first guess doesn't OOM identically on every attempt.
        mem_mb=lambda wildcards, attempt: _get_mem_mb("mark_duplicates", profile_config) * (2 ** (attempt - 1)),
    shell:
        r"""
        set -exo pipefail
        tmpdir_parent=$(dirname "{params.tmpdir}")
        mkdir -p "$tmpdir_parent"
        test -w "$tmpdir_parent" || {{ echo "mark_duplicates tempdir parent not writable: $tmpdir_parent" >&2; exit 1; }}
        rm -rf "{params.tmpdir}"
        mkdir -p "{params.tmpdir}"
        trap 'rm -rf "{params.tmpdir}"' EXIT
        outdir=$(dirname {output.bam})
        mkdir -p $outdir
        java_mem_mb=$(( {resources.mem_mb} * 80 / 100 ))
        java_mem_g=$(( java_mem_mb / 1024 ))
        if [ "$java_mem_g" -lt 4 ]; then
            java_mem_g=4
        fi
        picard -Xmx${{java_mem_g}}g -Djava.io.tmpdir={params.tmpdir} MarkDuplicates \
            I={input.bam} \
            O={output.bam} \
            M={output.metrics} \
            ASSUME_SORTED=true \
            TMP_DIR={params.tmpdir}
        picard -Xmx${{java_mem_g}}g BuildBamIndex I={output.bam} O={output.bai}
        ls -larth $outdir
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

rule rustqc_rna_combined_probe:
    # Only ever built when USE_INFER_STRANDEDNESS == "true" -- rustqc_rna_combined's own --stranded
    # lookup (params.stranded, via _get_rustqc_stranded below) is the only consumer of this rule's
    # output, and it only requests it in inference mode; in manifest-driven mode this rule never runs.
    #
    # --stranded here is a throwaway placeholder ("unstranded"): infer_experiment's own output is
    # unaffected by this flag (it empirically detects strandedness regardless, same as RSeQC's own
    # infer_experiment.py), and every other module this pass produces is discarded -- only
    # infer_experiment.txt is kept. rustqc's dupRadar/featureCounts modules cannot be disabled via
    # --config (confirmed empirically -- only tin/qualimap can), so this "probe" pass still runs the
    # full module suite; there is no cheaper way to isolate just infer_experiment in rustqc 0.2.1.
    input:
        bam = join(TEMPDIR, "mark_duplicates", "{sample}", "{sample}.markdup.bam"),
        bai = join(TEMPDIR, "mark_duplicates", "{sample}", "{sample}.markdup.bam.bai"),
        gtf = join(REF_DIR, "ref.fixed.gtf"),
    output:
        infer_experiment = temp(join(TEMPDIR, "rustqc_probe", "{sample}", "{sample}.Aligned.sortedByCoord.out.infer_experiment.txt")),
    params:
        sample = "{sample}",
        peorse = get_peorse,
        scratch = lambda wildcards: join(TEMPDIR, "rustqc_probe_scratch", wildcards.sample, str(uuid.uuid4())),
    container:
        config['containers']['rustqc'],
    threads: _get_threads("rustqc_rna_combined_probe", profile_config)
    resources:
        # Observed OOM in production at the pipeline-wide 40G default (MaxRSS ~42GB) before
        # this rule's own set-resources entry was synced into the run's profile -- double the
        # base mem_mb on each retry as a safety net against future under-sizing too.
        mem_mb=lambda wildcards, attempt: _get_mem_mb("rustqc_rna_combined_probe", profile_config) * (2 ** (attempt - 1)),
    shell:
        r"""
        set -exo pipefail
        scratch_parent=$(dirname "{params.scratch}")
        mkdir -p "$scratch_parent"
        test -w "$scratch_parent" || {{ echo "rustqc_rna_combined_probe scratch parent not writable: $scratch_parent" >&2; exit 1; }}
        rm -rf "{params.scratch}"
        mkdir -p "{params.scratch}"
        trap 'rm -rf "{params.scratch}"' EXIT
        mkdir -p $(dirname {output.infer_experiment})
        stem={params.sample}.Aligned.sortedByCoord.out
        paired_flag=""
        if [ "{params.peorse}" == "PE" ]; then
            paired_flag="--paired"
        fi
        rustqc rna {input.bam} \
            --gtf {input.gtf} \
            ${{paired_flag}} \
            --stranded unstranded \
            --sample-name ${{stem}} \
            --threads {threads} \
            --flat-output \
            --outdir {params.scratch}
        cp {params.scratch}/${{stem}}.infer_experiment.txt {output.infer_experiment}
        rm -rf {params.scratch}
        """

def _rustqc_rna_combined_input(wildcards):
    d = {
        "bam": join(TEMPDIR, "mark_duplicates", wildcards.sample, f"{wildcards.sample}.markdup.bam"),
        "bai": join(TEMPDIR, "mark_duplicates", wildcards.sample, f"{wildcards.sample}.markdup.bam.bai"),
        "gtf": join(REF_DIR, "ref.fixed.gtf"),
    }
    if USE_INFER_STRANDEDNESS == "true":
        d["probe_infer_experiment"] = join(
            TEMPDIR, "rustqc_probe", wildcards.sample, f"{wildcards.sample}.Aligned.sortedByCoord.out.infer_experiment.txt"
        )
    return d

def _get_rustqc_stranded(wildcards, input):
    if USE_INFER_STRANDEDNESS == "true":
        return _infer_strand_from_rseqc_infer_experiment(str(input.probe_infer_experiment), INFER_FRACTION_THRESHOLD)
    return SAMPLESDF.loc[SAMPLESDF['sampleName'] == wildcards.sample, STRANDEDNESS_COLUMN].values[0]

rule rustqc_rna_combined:
    # Replaces infer_strandedness (quantify.smk), rseqc_read_distribution, and
    # downsample_bam_for_tin/rseqc_tin (this file) with a single rustqc invocation on the combined,
    # duplicate-marked bam, run at full depth (no downsampling -- see dremellab/HAROLD#56 and the
    # 2026-07-28 full-scale benchmark: ~45min total vs. 7.5-13h/sample for RSeQC's tin.py on a
    # downsampled input). Also adds dupRadar/preseq/featureCounts (net-new QC capability) and
    # rustqc's rnaseq-mode Qualimap (new, alongside the untouched bamqc-mode `qualimap` rule) --
    # one invocation covers all of this since rustqc always computes its whole module suite
    # regardless of which specific output is wanted.
    input:
        unpack(_rustqc_rna_combined_input),
    output:
        strandedness = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.strandedness.txt"),
        read_distribution = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.read_distribution.txt"),
        tin_summary = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.summary.txt"),
        tin_xls = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.tin.xls"),
        dupradar_matrix = join(RESULTSDIR, "{sample}", "dupradar", "{sample}_dupMatrix.txt"),
        dupradar_intercept_mqc = join(RESULTSDIR, "{sample}", "dupradar", "{sample}_dup_intercept_mqc.txt"),
        dupradar_curve_mqc = join(RESULTSDIR, "{sample}", "dupradar", "{sample}_duprateExpDensCurve_mqc.txt"),
        preseq = join(RESULTSDIR, "{sample}", "preseq", "{sample}.lc_extrap.txt"),
        featurecounts = join(RESULTSDIR, "{sample}", "featurecounts", "{sample}.featureCounts.tsv"),
        featurecounts_summary = join(RESULTSDIR, "{sample}", "featurecounts", "{sample}.featureCounts.tsv.summary"),
        biotype_counts = join(RESULTSDIR, "{sample}", "featurecounts", "{sample}.biotype_counts.tsv"),
        biotype_counts_mqc = join(RESULTSDIR, "{sample}", "featurecounts", "{sample}.biotype_counts_mqc.tsv"),
        biotype_counts_rrna_mqc = join(RESULTSDIR, "{sample}", "featurecounts", "{sample}.biotype_counts_rrna_mqc.tsv"),
        qualimap_rnaseq_html = join(RESULTSDIR, "{sample}", "qualimap_rnaseq", "qualimapReport.html"),
        qualimap_rnaseq_txt = join(RESULTSDIR, "{sample}", "qualimap_rnaseq", "rnaseq_qc_results.txt"),
    params:
        sample = "{sample}",
        peorse = get_peorse,
        stranded = _get_rustqc_stranded,
        scratch = lambda wildcards: join(TEMPDIR, "rustqc_combined_scratch", wildcards.sample, str(uuid.uuid4())),
    container:
        config['containers']['rustqc'],
    threads: _get_threads("rustqc_rna_combined", profile_config)
    resources:
        # Same rationale as rustqc_rna_combined_probe above -- double the base mem_mb on
        # each retry rather than failing identically on every attempt.
        mem_mb=lambda wildcards, attempt: _get_mem_mb("rustqc_rna_combined", profile_config) * (2 ** (attempt - 1)),
    shell:
        r"""
        set -exo pipefail
        scratch_parent=$(dirname "{params.scratch}")
        mkdir -p "$scratch_parent"
        test -w "$scratch_parent" || {{ echo "rustqc_rna_combined scratch parent not writable: $scratch_parent" >&2; exit 1; }}
        rm -rf "{params.scratch}"
        mkdir -p "{params.scratch}"
        trap 'rm -rf "{params.scratch}"' EXIT
        stem={params.sample}.Aligned.sortedByCoord.out
        paired_flag=""
        if [ "{params.peorse}" == "PE" ]; then
            paired_flag="--paired"
        fi
        rustqc rna {input.bam} \
            --gtf {input.gtf} \
            ${{paired_flag}} \
            --stranded {params.stranded} \
            --sample-name ${{stem}} \
            --threads {threads} \
            --flat-output \
            --outdir {params.scratch}

        mkdir -p $(dirname {output.strandedness})
        mkdir -p $(dirname {output.dupradar_matrix})
        mkdir -p $(dirname {output.preseq})
        mkdir -p $(dirname {output.featurecounts})
        mkdir -p $(dirname {output.qualimap_rnaseq_html})

        cp {params.scratch}/${{stem}}.infer_experiment.txt {output.strandedness}
        cp {params.scratch}/${{stem}}.read_distribution.txt {output.read_distribution}
        cp {params.scratch}/${{stem}}.summary.txt {output.tin_summary}
        cp {params.scratch}/${{stem}}.tin.xls {output.tin_xls}
        cp {params.scratch}/${{stem}}_dupMatrix.txt {output.dupradar_matrix}
        cp {params.scratch}/${{stem}}_dup_intercept_mqc.txt {output.dupradar_intercept_mqc}
        cp {params.scratch}/${{stem}}_duprateExpDensCurve_mqc.txt {output.dupradar_curve_mqc}
        cp {params.scratch}/${{stem}}.lc_extrap.txt {output.preseq}
        cp {params.scratch}/${{stem}}.featureCounts.tsv {output.featurecounts}
        cp {params.scratch}/${{stem}}.featureCounts.tsv.summary {output.featurecounts_summary}
        cp {params.scratch}/${{stem}}.biotype_counts.tsv {output.biotype_counts}
        cp {params.scratch}/${{stem}}.biotype_counts_mqc.tsv {output.biotype_counts_mqc}
        cp {params.scratch}/${{stem}}.biotype_counts_rrna_mqc.tsv {output.biotype_counts_rrna_mqc}

        # Qualimap's own report layout isn't stem-prefixed (unlike every other rustqc module) and its
        # raw_data_qualimapReport/images_qualimapReport subdirs are Qualimap's own internal convention,
        # not rustqc's -- copy them explicitly rather than assuming --flat-output touches them too.
        cp {params.scratch}/qualimapReport.html {output.qualimap_rnaseq_html}
        cp {params.scratch}/rnaseq_qc_results.txt {output.qualimap_rnaseq_txt}
        for d in raw_data_qualimapReport images_qualimapReport; do
            if [ -d "{params.scratch}/$d" ]; then
                cp -r "{params.scratch}/$d" $(dirname {output.qualimap_rnaseq_html})/
            fi
        done
        ls -larth $(dirname {output.strandedness})
        rm -rf {params.scratch}
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

rule alignment_summary:
    input:
        fastqvalidator_reports=expand(
            join(
                RESULTSDIR,
                "{sample}",
                "fastq_validation",
                "{sample}.fastq_validator.txt",
            ),
            sample=SAMPLES,
        ),
        cutadapt_reports=expand(
            join(RESULTSDIR, "{sample}", "trim", "{sample}.cutadapt.report.txt"),
            sample=SAMPLES,
        ),
        star_logs=expand(
            join(RESULTSDIR, "{sample}", "STAR", "{sample}.Log.final.out"),
            sample=SAMPLES,
        ),
        bams=expand(
            join(
                RESULTSDIR,
                "{sample}",
                "STAR",
                "{sample}.Aligned.sortedByCoord.out.bam",
            ),
            sample=SAMPLES,
        ),
        regions_host=join(REF_DIR, "ref.fa.regions.host"),
        regions_viruses=join(REF_DIR, "ref.fa.regions.viruses"),
        regions_additives=join(REF_DIR, "ref.fa.regions.additives"),
    output:
        summary=join(RESULTSDIR, "alignmentqc", "alignment_summary.tsv"),
    log:
        join(RESULTSDIR, "alignmentqc", "alignment_summary.log"),
    params:
        script=join(SCRIPTS_DIR, "_alignment_summary.py"),
    container: config["containers"]["pysam"]
    shell:
        r"""
        set -exo pipefail
        mkdir -p $(dirname {output.summary})
        exec > >(tee {log}) 2>&1
        python {params.script} \
            --results-dir {RESULTSDIR} \
            --regions-host {input.regions_host} \
            --regions-viruses {input.regions_viruses} \
            --regions-additives {input.regions_additives} \
            --output {output.summary}
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
        tmpdir=lambda wildcards: join(TEMPDIR, "rseqc_read_gc", wildcards.sample, wildcards.regionname, str(uuid.uuid4())),
    container:
        config['containers']['rseqc'],
    threads: _get_threads("rseqc_read_gc", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.read_gc})
        mkdir -p $outdir
        tmpdir_parent=$(dirname "{params.tmpdir}")
        mkdir -p "$tmpdir_parent"
        test -w "$tmpdir_parent" || {{ echo "rseqc_read_gc tempdir parent not writable: $tmpdir_parent" >&2; exit 1; }}
        rm -rf "{params.tmpdir}"
        mkdir -p "{params.tmpdir}"
        trap 'rm -rf "{params.tmpdir}"' EXIT
        cd $outdir
        read_GC.py \
            -i {input.bam} \
            -o ${{outdir}}/{params.sample}.{params.regionname}
        ls -larth $outdir
        """

def _rustqc_rna_region_input(wildcards):
    d = {
        "bam": join(RESULTSDIR, wildcards.sample, "STAR", f"{wildcards.sample}.{wildcards.regionname}.bam"),
        "gtf": join(REF_DIR, "ref.fixed.gtf"),
    }
    if USE_INFER_STRANDEDNESS == "true":
        d["probe_infer_experiment"] = join(
            TEMPDIR, "rustqc_probe", wildcards.sample, f"{wildcards.sample}.Aligned.sortedByCoord.out.infer_experiment.txt"
        )
    return d

rule rustqc_rna_region:
    # Replaces rseqc_junction_annotation. Runs per {regionname} split bam (same wildcard split_bam in
    # visualize.smk already produces) -- not touched by mark_duplicates, since duplicates aren't
    # relevant to junction detection and this bam was never claimed to be duplicate-marked, hence
    # --skip-dup-check here (unlike rustqc_rna_combined, which legitimately is fed a marked bam and
    # wants that check enforced). TIN and qualimap are explicitly disabled since only junction_annotation
    # is used from this pass -- dupRadar/featureCounts still run regardless (can't be disabled, see
    # rustqc_rna_combined_probe's comment) but are simply left unused/undeclared here.
    input:
        unpack(_rustqc_rna_region_input),
    output:
        junctions = join(RESULTSDIR, "{sample}", "rseqc", "{sample}.{regionname}.junction.bed"),
    params:
        sample = "{sample}",
        regionname = "{regionname}",
        peorse = get_peorse,
        stranded = _get_rustqc_stranded,
        scratch = lambda wildcards: join(TEMPDIR, "rustqc_region_scratch", wildcards.sample, wildcards.regionname, str(uuid.uuid4())),
    container:
        config['containers']['rustqc'],
    threads: _get_threads("rustqc_rna_region", profile_config)
    resources:
        # Same rationale as rustqc_rna_combined_probe above -- double the base mem_mb on
        # each retry rather than failing identically on every attempt.
        mem_mb=lambda wildcards, attempt: _get_mem_mb("rustqc_rna_region", profile_config) * (2 ** (attempt - 1)),
    shell:
        r"""
        set -exo pipefail
        scratch_parent=$(dirname "{params.scratch}")
        mkdir -p "$scratch_parent"
        test -w "$scratch_parent" || {{ echo "rustqc_rna_region scratch parent not writable: $scratch_parent" >&2; exit 1; }}
        rm -rf "{params.scratch}"
        mkdir -p "{params.scratch}"
        trap 'rm -rf "{params.scratch}"' EXIT
        outdir="$(dirname {output.junctions})"
        mkdir -p "${{outdir}}"
        stem={params.sample}.{params.regionname}
        paired_flag=""
        if [ "{params.peorse}" == "PE" ]; then
            paired_flag="--paired"
        fi
        cat > {params.scratch}/skip_qualimap.yaml <<'YAML'
rna:
  qualimap:
    enabled: false
YAML
        rustqc rna {input.bam} \
            --gtf {input.gtf} \
            ${{paired_flag}} \
            --stranded {params.stranded} \
            --sample-name ${{stem}} \
            --skip-dup-check \
            --skip-tin \
            --config {params.scratch}/skip_qualimap.yaml \
            --threads {threads} \
            --flat-output \
            --outdir {params.scratch}
        # Create output file if it doesn't exist (no junctions found case)
        if [ -f "{params.scratch}/${{stem}}.junction.bed" ]; then
            cp "{params.scratch}/${{stem}}.junction.bed" "{output.junctions}"
        else
            touch "{output.junctions}"
        fi
        ls -larth "${{outdir}}"
        rm -rf {params.scratch}
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
        tmpdir=lambda wildcards: join(TEMPDIR, "junctions_to_bigbed", wildcards.sample, wildcards.regionname, str(uuid.uuid4())),
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
        tmpdir_parent=$(dirname "{params.tmpdir}")
        mkdir -p "$tmpdir_parent"
        test -w "$tmpdir_parent" || {{ echo "junctions_to_bigbed tempdir parent not writable: $tmpdir_parent" >&2; exit 1; }}
        rm -rf "{params.tmpdir}"
        mkdir -p "{params.tmpdir}"
        trap 'rm -rf "{params.tmpdir}"' EXIT
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
        # rseqc_geneBody_coverage is deliberately NOT required here -- it fails to complete for most
        # samples in production (see dremellab/HAROLD#56); qualimap_rnaseq's coverage profile below is
        # the practical interim gene-body-coverage-style signal instead.
        expand(join(RESULTSDIR, "{sample}", "rseqc", "{sample}.Aligned.sortedByCoord.out.summary.txt")      ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "kraken2", "{sample}.kraken2.report.txt")                       ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "dupradar", "{sample}_dupMatrix.txt")                           ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "preseq", "{sample}.lc_extrap.txt")                             ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "featurecounts", "{sample}.featureCounts.tsv")                  ,sample=SAMPLES),
        expand(join(RESULTSDIR, "{sample}", "qualimap_rnaseq", "qualimapReport.html")                       ,sample=SAMPLES),
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
