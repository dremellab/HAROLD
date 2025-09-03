## functions



## rules


rule cutadapt:
    input:
        unpack(get_fastqs),
    output:
        of1=join(WORKDIR, "results", "{sample}", "trim", "{sample}.R1.trim.fastq.gz"),
        of2=join(WORKDIR, "results", "{sample}", "trim", "{sample}.R2.trim.fastq.gz"),
    params:
        sample="{sample}",
        workdir=WORKDIR,
        outdir=join(RESULTSDIR, "{sample}"),
        peorse=get_peorse,
        cutadapt_min_length=config["cutadapt_min_length"],
        cutadapt_n=config["cutadapt_n"],
        cutadapt_max_n=config["cutadapt_max_n"],
        cutadapt_O=config["cutadapt_O"],
        cutadapt_q=config["cutadapt_q"],
        adapters=join(RESOURCES_DIR, "adapters.fa"),
        tmpdir=temp(f"{TEMPDIR}/{str(uuid.uuid4())}"),
    container: config['containers']['cutadapt']
    # threads: getthreads("cutadapt")
    # threads: 4
    # threads: resources.threads
    # threads:
    #     profile_config['set-resources']['cutadapt']['threads']
    #     if 'cutadapt' in profile_config['set-resources'] and 'threads' in profile_config['set-resources']['cutadapt']
    #     else profile_config['default-resources']['threads']
    threads: _get_threads("cutadapt", profile_config)
    shell:
        """
        set -exo pipefail

        mkdir -p {params.tmpdir}
        of1bn=$(basename {output.of1})
        of2bn=$(basename {output.of2})

        if [ "{params.peorse}" == "PE" ];then
            ## Paired-end
            cutadapt --pair-filter=any \\
            --nextseq-trim=2 \\
            --trim-n \\
            --max-n {params.cutadapt_max_n} \\
            -n {params.cutadapt_n} -O {params.cutadapt_O} \\
            -q {params.cutadapt_q},{params.cutadapt_q} -m {params.cutadapt_min_length}:{params.cutadapt_min_length} \\
            -b file:{params.adapters} \\
            -B file:{params.adapters} \\
            -j {threads} \\
            -o {params.tmpdir}/${{of1bn}} -p {params.tmpdir}/${{of2bn}} \\
            {input.R1} {input.R2}

        # filter for average read quality
            fastq-filter \\
                -q {params.cutadapt_q} \\
                -o {output.of1} -o {output.of2} \\
                {params.tmpdir}/${{of1bn}} {params.tmpdir}/${{of2bn}}

        else
            ## Single-end
            cutadapt \\
            --nextseq-trim=2 \\
            --trim-n \\
            --max-n {params.cutadapt_max_n} \\
            -n {params.cutadapt_n} -O {params.cutadapt_O} \\
            -q {params.cutadapt_q},{params.cutadapt_q} -m {params.cutadapt_min_length} \\
            -b file:{params.adapters} \\
            -j {threads} \\
            -o {params.tmpdir}/${{of1bn}} \\
            {input.R1}

            touch {output.of2}

        # filter for average read quality
            fastq-filter \\
                -q {params.cutadapt_q} \\
                -o {output.of1} \\
                {params.tmpdir}/${{of1bn}}

        fi
        """
