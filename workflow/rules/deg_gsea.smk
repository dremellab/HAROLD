
rule diffex_deg:
    input:
        counts = join(RESULTSDIR, "counts", "counts_matrix.tsv"),
    output:
        results = expand(
            join(RESULTSDIR, "counts", "DEG", "{{contrast}}_{{variant}}", "{method}_deg", "{method}_results.tsv"),
            method=METHODS,
        ),
        rnks = expand(
            join(RESULTSDIR, "counts", "DEG", "{{contrast}}_{{variant}}", "{method}_deg", "{method}_gsea.rnk"),
            method=METHODS,
        ),
    wildcard_constraints:
        variant = "|".join(VARIANTS.keys()) if VARIANTS else "NOVARIANT",
    params:
        manifest_file = MANIFEST_FILE,
        group1 = lambda wc: CONTRAST2GROUPS[wc.contrast][0],
        group2 = lambda wc: CONTRAST2GROUPS[wc.contrast][1],
        use_ercc = lambda wc: VARIANTS[wc.variant][0],
        use_batch = lambda wc: VARIANTS[wc.variant][1],
        ercc_mix = str(config.get('diffex_deg_gsea', {}).get('ercc_mix', '1')),
        batch_column = str(config.get('diffex_deg_gsea', {}).get('batch_column', 'batch')),
        genes_selection = str(config.get('diffex_deg_gsea', {}).get('genes_selection', 'both')).lower(),
        host = DIFFEX_HOST,
        log2fc_threshold = config.get('diffex_deg_gsea', {}).get('log2fc_threshold', 1.0),
        pvalue_threshold = config.get('diffex_deg_gsea', {}).get('pvalue_threshold', 0.05),
        fdr_threshold = config.get('diffex_deg_gsea', {}).get('fdr_threshold', 0.05),
        edger_cpm_cutoff = config.get('diffex_deg_gsea', {}).get('edger_cpm_cutoff', 0.1),
        edger_cpm_group_fraction = config.get('diffex_deg_gsea', {}).get('edger_cpm_group_fraction', 0.5),
        deseq2_low_count_cutoff = config.get('diffex_deg_gsea', {}).get('deseq2_low_count_cutoff', 2),
        deseq2_low_count_group_fraction = config.get('diffex_deg_gsea', {}).get('deseq2_low_count_group_fraction', 0.5),
    container:
        config['containers']['diffex']
    threads: _get_threads("diffex_deg", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname $(dirname {output.results[0]}))
        mkdir -p $outdir
        if [ "{params.use_ercc}" = "True" ]; then
            ercc_arg="--use-ercc --ercc-mix {params.ercc_mix}"
        else
            ercc_arg=""
        fi
        if [ "{params.use_batch}" = "True" ]; then
            batch_arg="--use-batch --batch-column {params.batch_column}"
        else
            batch_arg=""
        fi
        cd /app/DiffEx
        diffex deg \
            --counts-file {input.counts} \
            -s {params.manifest_file} \
            --group1 {params.group1} \
            --group2 {params.group2} \
            $ercc_arg \
            $batch_arg \
            --sample-column sampleName \
            --group-column groupName \
            -o $outdir \
            --host {params.host} \
            --genes-selection {params.genes_selection} \
            --log2fc-threshold {params.log2fc_threshold} \
            --pvalue-threshold {params.pvalue_threshold} \
            --fdr-threshold {params.fdr_threshold} \
            --edger-cpm-cutoff {params.edger_cpm_cutoff} \
            --edger-cpm-group-fraction {params.edger_cpm_group_fraction} \
            --deseq2-low-count-cutoff {params.deseq2_low_count_cutoff} \
            --deseq2-low-count-group-fraction {params.deseq2_low_count_group_fraction}
        ls -alrth $outdir
        """


rule warm_msigdb_cache:
    # diffex gsea's msigdbr call downloads+caches MSigDB gene sets to a shared
    # location (the container's $HOME, which is the workdir itself). Running
    # this once up front, before any diffex_gsea job, avoids many concurrent
    # jobs racing to populate that same cache file on a fresh workdir.
    output:
        touch(join(WORKDIR, ".msigdb_cache_warm")),
    params:
        db_species = DIFFEX_HOST,
    container:
        config['containers']['diffex']
    threads: _get_threads("warm_msigdb_cache", profile_config)
    shell:
        r"""
        set -exo pipefail
        Rscript -e 'suppressPackageStartupMessages(library(msigdbr)); msigdbr::msigdbr_collections(db_species = "{params.db_species}")'
        """


rule diffex_gsea:
    input:
        rnk = join(RESULTSDIR, "counts", "DEG", "{contrast}_{variant}", "{method}_deg", "{method}_gsea.rnk"),
        cache_warm = join(WORKDIR, ".msigdb_cache_warm"),
    output:
        xlsx = join(RESULTSDIR, "counts", "GSEA", "{contrast}_{variant}", "{method}", "GSEA_results.xlsx"),
        html = join(RESULTSDIR, "counts", "GSEA", "{contrast}_{variant}", "{method}", "gsea.html"),
    wildcard_constraints:
        variant = "|".join(VARIANTS.keys()) if VARIANTS else "NOVARIANT",
        method = "|".join(METHODS),
    params:
        min_gs_size = config.get('diffex_deg_gsea', {}).get('gsea_min_gs_size', 15),
        max_gs_size = config.get('diffex_deg_gsea', {}).get('gsea_max_gs_size', 500),
        pvalue_cutoff = config.get('diffex_deg_gsea', {}).get('gsea_pvalue_cutoff', 0.05),
        script = join(SCRIPTS_DIR, "_sanitize_rnk.py"),
    container:
        config['containers']['diffex']
    threads: _get_threads("diffex_gsea", profile_config)
    shell:
        r"""
        set -exo pipefail
        outdir=$(dirname {output.xlsx})
        mkdir -p $outdir
        sanitized_rnk=$outdir/{wildcards.method}_gsea.sanitized.rnk
        python {params.script} --input {input.rnk} --output $sanitized_rnk
        cd /app/DiffEx
        diffex gsea \
            --rnk $sanitized_rnk \
            -o $outdir \
            --min-gs-size {params.min_gs_size} \
            --max-gs-size {params.max_gs_size} \
            --pvalue-cutoff {params.pvalue_cutoff}
        ls -alrth $outdir
        """
