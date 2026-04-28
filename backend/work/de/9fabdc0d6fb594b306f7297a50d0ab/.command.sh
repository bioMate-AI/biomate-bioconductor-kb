#!/usr/bin/env bash -C -e -u -o pipefail
# Not calling gunzip itself because it creates files
# with the original group ownership rather than the
# default one for that user / the work directory
gzip \
    -cd \
     \
    gfp.fa.gz \
    > gfp.fa

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:PREPARE_GENOME:GUNZIP_ADDITIONAL_FASTA":
    gunzip: $(echo $(gunzip --version 2>&1) | sed 's/^.*(gzip) //; s/ Copyright.*$//')
END_VERSIONS
