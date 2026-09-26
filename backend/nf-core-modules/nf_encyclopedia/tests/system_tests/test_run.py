"""Test on real data"""
import subprocess
import os


def test_run(real_data, tmp_path):
    """Test the workflow on real data"""

    # CI is set to true in the github action
    # NFE_CONTAINER is just a variable to help in future debugging,
    # if set will use that tag to execute local jobs
    if "CI" in os.environ:
        docker_tag = "nf-encyclopedia"
    elif "NFE_CONTAINER" not in os.environ:
        docker_tag = "ghcr.io/talusbio/nf-encyclopedia:latest"
    else:
        docker_tag = os.environ["NFE_CONTAINER"]

    os.environ["NFE_CONTAINER"] = docker_tag
    config, _ = real_data
    cmd = ["nextflow", "run", "main.nf"] + config
    subprocess.run(cmd, check=True)
