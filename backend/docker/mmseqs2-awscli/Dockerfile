FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86

# Install mmseqs2 static binary (AVX2) — statically linked.
# NOTE: do NOT run `mmseqs version` here; this image is built on ARM64 under QEMU
# and AVX2 instructions are not emulated — verification runs on real x86 at job start.
RUN curl -sSfL https://mmseqs.com/latest/mmseqs-linux-avx2.tar.gz \
    | tar -xz -C /usr/local/ \
    && ln -sf /usr/local/mmseqs/bin/mmseqs /usr/local/bin/mmseqs \
    && ls -lh /usr/local/bin/mmseqs

WORKDIR /data
