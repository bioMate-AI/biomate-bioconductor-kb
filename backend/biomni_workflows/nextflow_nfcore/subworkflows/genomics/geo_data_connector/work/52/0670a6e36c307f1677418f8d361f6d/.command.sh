#!/bin/bash -ue
echo '"sample_id","time","event","treatment","age","sex"' > clinical_metadata_clean.csv
echo '"GSM1","24","1","Drug_A_100nM","55","male"' >> clinical_metadata_clean.csv
cat <<-END_VERSIONS > versions.yml
"GEO_DATA_CONNECTOR:GEO_CLINICAL_METADATA":
    r-base: "4.4.0 (stub)"
    bioconductor-geoquery: "2.72.0 (stub)"
END_VERSIONS
