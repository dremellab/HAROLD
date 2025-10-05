#!/bin/bash
#SBATCH --cpus-per-task={threads}
#SBATCH --mem={resources.mem_mb}
#SBATCH --time={resources.runtime}
#SBATCH --output=logs/{rule}.{jobid}.slurm-%j.out
#SBATCH --error=logs/{rule}.{jobid}.slurm-%j.err

{exec_job}
