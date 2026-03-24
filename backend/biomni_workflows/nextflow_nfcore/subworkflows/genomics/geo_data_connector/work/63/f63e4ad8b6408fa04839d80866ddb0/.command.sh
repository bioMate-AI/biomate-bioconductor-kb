#!/bin/bash -ue
touch series_matrix.rds
echo '"geo_accession","title","source_name_ch1","organism_ch1"' > sample_metadata.csv
echo '"GSM1","Sample_1","tumor","Homo sapiens"' >> sample_metadata.csv
cat <<-END_VERSIONS > versions.yml
"GEO_DATA_CONNECTOR:GEO_FETCH":
    r-base: "4.4.0 (stub)"
    bioconductor-geoquery: "2.72.0 (stub)"
END_VERSIONS
