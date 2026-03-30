#!/bin/bash -ue
echo '"gene_id","GSM1","GSM2"' > count_matrix.csv
echo '"GAPDH","100","120"' >> count_matrix.csv
echo '"ID","Symbol"' > feature_metadata.csv
echo '"GAPDH","GAPDH"' >> feature_metadata.csv
cat <<-END_VERSIONS > versions.yml
"GEO_DATA_CONNECTOR:GEO_COUNT_MATRIX":
    r-base: "4.4.0 (stub)"
    bioconductor-geoquery: "2.72.0 (stub)"
END_VERSIONS
