## updates:

 - **Added DEG + GSEA**. 
 
     - The pipeline can now run differential gene expression and gene set enrichment as a built-in step, instead of that being a separate manual process. This is the headline feature of the upcoming v2.0.0 release.

     - v0.5.5 of DiffEx created to correct for possibility of -Inf/Inf ranking scores resulting from very small p-values

  - **4SU1**
    
    - Added support for a new spike-in control (4SU1) so studies using it are now fully recognized by the pipeline.

    - The summary report will now show how many reads mapped to spike-in controls (like ERCC or 4SU1) for each sample

  - **Tracking and logging improvements**

    - INFO/NEXT/OK etc. prefix to each line on terminal at run-time making it easier for the user to follow what is currently happening during pipeline run

    - Added clearer run tracking and logging, so it's easier to tell what stage a run is in and whether it succeeded, failed, or is still going. Added pipeline.running/.failed/.completed files in the output folder

  - **other maintenance/improvements**

    - Fixed several reliability issues: runs sometimes reported the wrong status, occasionally got "stuck" (failed to release their lock), and cloud (S3) uploads could start before results were fully ready.

    - Fixed a memory error that was causing sample-file validation to crash on larger datasets.

    - Packaged and documented version 2.0.0 — release notes, a full documentation review/cleanup, and fixes to inaccuracies found during that review.

