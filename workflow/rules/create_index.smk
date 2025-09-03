rule create_index:
    input:
        # FASTAS_REGIONS_GTFS
        list(map(lambda x: ancient(x), FASTAS_REGIONS_GTFS)),
    output:
        genepred_w_geneid = join(REF_DIR, "ref.genes.genepred_w_geneid"),
        sa = join(STAR_INDEX_DIR, "SA"),
        fixed_gtf=join(REF_DIR, "ref.fixed.gtf"),
    params:
        reffa=REF_FA,
        refgtf=REF_GTF,
        refdir=REF_DIR,
        script1=join(SCRIPTS_DIR, "_fix_gtf.py"),
        script2=join(SCRIPTS_DIR, "_add_geneid_to_genepred.py"),
    container: config['containers']['star_ucsc_cufflinks']
    # threads: getthreads("create_index")
    # threads: 1
    shell:
        """
set -exo pipefail
cd {params.refdir}
samtools faidx {params.reffa} && \\
    cut -f1-2 {params.reffa}.fai > {params.reffa}.sizes

python -E {params.script1} --ingtf {params.refgtf} --outgtf {output.fixed_gtf}
gtfToGenePred -ignoreGroupsWithoutExons {output.fixed_gtf} ref.genes.genepred && \\
    python -E {params.script2} {output.fixed_gtf} ref.genes.genepred > {output.genepred_w_geneid}

stardir=$(dirname {output.sa})
mkdir -p $stardir && \\
STAR \\
    --runThreadN {threads} \\
    --runMode genomeGenerate \\
    --genomeDir $stardir \\
    --genomeFastaFiles {params.reffa}

"""
