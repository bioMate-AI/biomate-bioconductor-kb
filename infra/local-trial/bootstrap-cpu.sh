#!/bin/bash
set -euo pipefail
shutdown -h +180
mkdir -p /opt/biomate-trial
chown ubuntu:ubuntu /opt/biomate-trial
exec > >(tee -a /opt/biomate-trial/bootstrap.log) 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git cmake pkg-config build-essential libcurl4-openssl-dev libopenblas-dev python3-venv unzip
free -h
printf 'CPU preparation ready\n' > /opt/biomate-trial/CPU_READY
