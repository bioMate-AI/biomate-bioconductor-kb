#!/bin/bash -ue
touch test_km_fit.rds
touch test_km_summary.csv
echo "0.05" > test_logrank_pvalue.txt
echo "CRAN_SURVIVAL_KAPLANMEIER:" > versions.yml
echo "    survival: 0.0.0" >> versions.yml
