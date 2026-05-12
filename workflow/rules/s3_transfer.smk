rule s3_transfer_if_enabled:
    """
    Conditionally transfer pipeline results to S3 at the end of a successful run.
    Only executes if push_to_s3=true in config.
    """
    input:
        # Depend on key final outputs to avoid circular dependency with rule all
        join(RESULTSDIR, "multiqc_report.html"),
        join(RESULTSDIR,"counts","counts_matrix.tsv"),
        join(RESULTSDIR, "alignmentqc", "alignment_summary.tsv"),
    output:
        sentinel=".s3_transfer.done",
    container:
        config["containers"]["aws"]
    params:
        s3_enabled=config.get("push_to_s3", False),
        pipeline_name=config.get("s3_pipeline_name", "HAROLD"),
        sample_set=config.get("s3_sample_set_name", ""),
        creds_file=config.get("s3_aws_credentials_file", "/project/dremel_lab/scripts/aws/credentials"),
        bucket=config.get("s3_bucket", "dremel-lab-bucket"),
        s3_prefix=config.get("s3_output_prefix", "_HTS"),
        default_storage=config.get("s3_default_storage_class", "GLACIER_IR"),
        large_file_storage=config.get("s3_large_file_storage_class", "GLACIER"),
        scriptsdir=SCRIPTS_DIR,
    shell:
        """
        if [ "{params.s3_enabled}" = "True" ] || [ "{params.s3_enabled}" = "true" ]; then
            if [ -z "{params.sample_set}" ]; then
                echo "ERROR: s3_sample_set_name is required when push_to_s3=true"
                exit 1
            fi
            export AWS_SHARED_CREDENTIALS_FILE={params.creds_file}
            export AWS_PROFILE=s3-globus-user
            python3 {params.scriptsdir}/s3_transfer_harold.py \\
                --workdir "$(pwd)" \\
                --pipeline-name "{params.pipeline_name}" \\
                --sample-set-name "{params.sample_set}" \\
                --bucket "{params.bucket}" \\
                --s3-prefix "{params.s3_prefix}" \\
                --storage-class {params.default_storage} \\
                --large-file-storage-class {params.large_file_storage} \\
                && touch {output.sentinel} \\
                || exit 1
        else
            echo "S3 transfer disabled (push_to_s3=false)"
            touch {output.sentinel}
        fi
        """
