#!/usr/bin/env python3
"""
SLURM job status script with successful log archiving.
"""
import re
import subprocess as sp
import shlex
import sys
import time
import logging
from pathlib import Path

logger = logging.getLogger("__name__")

STATUS_MAP = {
    "BOOT_FAIL": "failed",
    "CANCELLED": "failed",
    "COMPLETED": "success",
    "DEADLINE": "failed",
    "FAILED": "failed",
    "NODE_FAIL": "failed",
    "OUT_OF_MEMORY": "failed",
    "PENDING": "running",
    "PREEMPTED": "failed",
    "RUNNING": "running",
    "REQUEUED": "running",
    "SUSPENDED": "running",
    "TIMEOUT": "failed",
}

def parse_jobid(jobid):
    """Extract jobid from job string"""
    if not isinstance(jobid, str):
        return jobid
    try:
        return int(jobid)
    except ValueError:
        match = re.match(r"(\d+)", jobid)
        if match:
            return int(match.groups()[0])
        return jobid

def archive_successful_log(jobid):
    """Move successful job logs to successful_jobs directory"""
    try:
        # Find the log file
        log_file = Path(f"slurm-{jobid}.out")
        if not log_file.exists():
            return

        # Create successful_jobs directory if it doesn't exist
        success_dir = Path("logs/successful_jobs")
        success_dir.mkdir(parents=True, exist_ok=True)

        # Move the log file
        log_file.rename(success_dir / log_file.name)
    except Exception as e:
        logger.error(f"Error archiving log for job {jobid}: {e}")

def get_status(jobid):
    """Get status for jobid."""
    jobid = parse_jobid(jobid)
    
    try:
        sacct_cmd = shlex.split(
            f"sacct -j {jobid} -n -P -X --format=state,exitcode"
        )
        output = sp.check_output(sacct_cmd).decode()
    except sp.CalledProcessError as e:
        logger.error(f"sacct error: {e}")
        return "failed"

    state = ""
    for line in output.split("\n"):
        if not line.strip():
            continue
        state, exitcode = line.strip().split("|")[:2]
        if state == "COMPLETED" and exitcode == "0:0":
            archive_successful_log(jobid)  # Archive successful job log
            return "success"
        if state in STATUS_MAP:
            return STATUS_MAP[state]
        return "running"

    return "failed"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(get_status(sys.argv[1]))
    else:
        print("No jobid provided", file=sys.stderr)
        sys.exit(1)