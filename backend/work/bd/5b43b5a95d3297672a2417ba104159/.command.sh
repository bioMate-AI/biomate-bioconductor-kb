#!/usr/bin/env bash -C -e -u -o pipefail
# Not calling gunzip itself because it creates files
# with the original group ownership rather than the
# default one for that user / the work directory
gzip \
    -cd \
     \
    genes_with_empty_tid.gtf.gz \
    > genes_with_empty_tid.gtf

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:PREPARE_GENOME:GUNZIP_GTF":
    gunzip: $(echo $(gunzip --version 2>&1) | sed 's/^.*(gzip) //; s/ Copyright.*$//')
END_VERSIONS
