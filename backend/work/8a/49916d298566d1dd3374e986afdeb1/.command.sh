#!/usr/bin/env bash -C -e -u -o pipefail
mkdir salmon

## Ensures --strip-components only applied when top level of tar contents is a directory
## If just files or multiple directories, place all in prefix
if [[ $(tar -taf salmon.tar.gz | grep -o -P "^.*?\/" | uniq | wc -l) -eq 1 ]]; then
    tar \
        -C salmon --strip-components 1 \
        -xavf \
         \
        salmon.tar.gz \
        --no-same-owner
else
    tar \
        -C salmon \
        -xavf \
         \
        salmon.tar.gz \
        --no-same-owner
fi

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:PREPARE_GENOME:UNTAR_SALMON_INDEX":
    untar: $(echo $(tar --version 2>&1) | sed 's/^.*(GNU tar) //; s/ Copyright.*$//')
END_VERSIONS
