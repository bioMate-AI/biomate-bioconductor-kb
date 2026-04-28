FROM python:3.11-slim

LABEL maintainer="biomate" \
      description="CryoSPARC Nextflow orchestration container — cryosparc-tools client + AWS utilities" \
      version="1.0.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        unzip \
        jq \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 at /opt/aws-cli — matches Nextflow cliPath = '/opt/aws-cli/bin/aws'
# so the container is self-sufficient even if the host bind-mount is missing/empty
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install Python packages
RUN pip install --no-cache-dir \
        cryosparc-tools \
        boto3 \
        numpy

CMD ["python3"]
