## functions



## rules


rule fastq_validate_sample:
    input:
        unpack(get_fastqs),
    output:
        report=join(WORKDIR, "results", "{sample}", "fastq_validation", "{sample}.fastq_validator.txt"),
        ok=join(WORKDIR, "results", "{sample}", "fastq_validation", "{sample}.ok"),
    params:
        peorse=get_peorse,
        outdir=join(RESULTSDIR, "{sample}", "fastq_validation"),
    container: config["containers"]["fastqvalidator"]
    threads: 1
    shell:
        r"""
        set -euo pipefail

        mkdir -p "{params.outdir}"
        : > "{output.report}"

        run_validator() {{
            fq="$1"
            tmp_report=$(mktemp "{params.outdir}/{wildcards.sample}.XXXXXX.fastq_validator.tmp")
            tmp_fastq=$(mktemp "{params.outdir}/{wildcards.sample}.XXXXXX.fastq")

            echo "Validating ${{fq}}" | tee -a "{output.report}"
            if ! gzip -dc "$fq" > "$tmp_fastq"; then
                rm -f "$tmp_fastq"
                echo "ERROR: gzip -d failed for ${{fq}}. fastQValidator will not run." | tee -a "{output.report}" >&2
                exit 1
            fi

            if ! fastQValidator --file "$tmp_fastq" > "$tmp_report" 2>&1; then
                cat "$tmp_report" >> "{output.report}"
                rm -f "$tmp_fastq"
                echo "ERROR: fastQValidator failed for ${{fq}}. cutadapt will not run." | tee -a "{output.report}" >&2
                exit 1
            fi

            cat "$tmp_report" >> "{output.report}"

            if ! grep -Fq "Returning: 0 : FASTQ_SUCCESS" "$tmp_report"; then
                rm -f "$tmp_fastq"
                echo "ERROR: FASTQ_SUCCESS not found for ${{fq}}. The FASTQ may be incomplete or corrupted. cutadapt will not run." | tee -a "{output.report}" >&2
                exit 1
            fi

            rm -f "$tmp_fastq"
        }}

        run_validator "{input.R1}"

        if [ "{params.peorse}" = "PE" ]; then
            run_validator "{input.R2}"
        fi

        echo "FASTQ validation passed for sample {wildcards.sample}." | tee -a "{output.report}"
        touch "{output.ok}"
        """

rule cutadapt:
    input:
        unpack(get_fastqs),
        validation=rules.fastq_validate_sample.output.ok,
    output:
        of1=join(WORKDIR, "results", "{sample}", "trim", "{sample}.R1.trim.fastq.gz"),
        of2=join(WORKDIR, "results", "{sample}", "trim", "{sample}.R2.trim.fastq.gz"),
        report=join(WORKDIR, "results", "{sample}", "trim", "{sample}.cutadapt.report.txt"),
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
        mkdir -p $(dirname {output.of1})
        exec > >(tee {output.report}) 2>&1
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
