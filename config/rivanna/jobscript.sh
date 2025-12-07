#!/bin/bash
#SBATCH --cpus-per-task={threads}
#SBATCH --mem={resources.mem_mb}
#SBATCH --time={resources.runtime}
#SBATCH --account=dremel_lab
#SBATCH --output=logs/{rule}.{jobid}.slurm-%j.out
#SBATCH --error=logs/{rule}.{jobid}.slurm-%j.err

source ~/.bashrc
export PROFILE={profile}

SCRATCH_ROOT="${SCRATCH:-/scratch/$USER}"
if [[ ! -d "$SCRATCH_ROOT" ]]; then
  mkdir -p "$SCRATCH_ROOT" 2>/dev/null || SCRATCH_ROOT="$PWD/.harold_runtime"
fi

APPTAINER_RUNTIME_ROOT="${SCRATCH_ROOT}/apptainer"
APPTAINER_SIF_DIR="${APPTAINER_RUNTIME_ROOT}/sif"
APPTAINER_CACHE_DIR="${APPTAINER_RUNTIME_ROOT}/cache"
APPTAINER_TMP_DIR="${APPTAINER_RUNTIME_ROOT}/tmp"

mkdir -p "$APPTAINER_SIF_DIR" "$APPTAINER_CACHE_DIR" "$APPTAINER_TMP_DIR"

export APPTAINER_CACHEDIR="$APPTAINER_CACHE_DIR"
export SINGULARITY_CACHEDIR="$APPTAINER_CACHE_DIR"
export APPTAINER_TMPDIR="$APPTAINER_TMP_DIR"
export SINGULARITY_TMPDIR="$APPTAINER_TMP_DIR"
export APPTAINER_PULLDIR="$APPTAINER_SIF_DIR"
export TMPDIR="$APPTAINER_TMP_DIR"

{exec_job}
