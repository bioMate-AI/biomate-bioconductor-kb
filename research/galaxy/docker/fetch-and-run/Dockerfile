# AWS Batch Fetch-and-Run Image for Galaxy Cloud Executor
#
# This image is used as a wrapper to execute Galaxy tools in any BioContainer.
# It handles S3 file transfers and container orchestration.

FROM amazonlinux:2

# Install AWS CLI, Python, and Docker client for Docker-in-Docker support
# UNIVERSAL RUNTIME: Install Python + common bioinformatics tools (covers 90%)
# R will be installed via dynamic installation if needed (covers remaining 10%)
RUN yum update -y && \
    yum install -y \
        python3 \
        python3-pip \
        python3-devel \
        perl \
        perl-core \
        gcc \
        gcc-c++ \
        make \
        aws-cli \
        tar \
        gzip \
        bzip2 \
        wget \
        curl \
        unzip \
        which \
        findutils \
        sed \
        awk \
        grep && \
    pip3 install --no-cache-dir boto3 numpy pandas biopython scipy scikit-learn && \
    yum clean all

# Enable EPEL and install R with development libraries (A+B solution)
RUN amazon-linux-extras install epel -y && \
    yum install -y \
        R \
        libxml2-devel \
        libcurl-devel \
        openssl-devel \
        libpng-devel \
        cairo-devel && \
    yum clean all

# Pre-install BiocManager and most critical R packages (minimal set)
# Only install: BiocManager (universal installer) and getopt (most commonly needed)
RUN Rscript -e "install.packages(c('BiocManager', 'getopt'), repos='https://cloud.r-project.org/', Ncpus=2)" && \
    echo "BiocManager and getopt installed"

# Verify all runtimes
RUN python3 --version && \
    perl --version && \
    R --version && \
    echo "All runtimes ready"

# Install Docker CLI from official Docker repository
# Amazon Linux 2 doesn't have docker in default repos
# Auto-detect architecture (x86_64 or aarch64)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then DOCKER_ARCH="aarch64"; \
    elif [ "$ARCH" = "x86_64" ]; then DOCKER_ARCH="x86_64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    echo "Downloading Docker CLI for $DOCKER_ARCH..." && \
    curl -fsSL https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-20.10.9.tgz -o docker.tgz && \
    tar --extract --file docker.tgz --strip-components 1 --directory /usr/local/bin/ docker/docker && \
    rm docker.tgz && \
    docker --version

# Copy the fetch-and-run script
COPY fetch_and_run.sh /usr/local/bin/fetch_and_run.sh
RUN chmod +x /usr/local/bin/fetch_and_run.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/fetch_and_run.sh"]
