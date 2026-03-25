#!/bin/bash -ue
touch patient_stratification_km_fit.rds
touch patient_stratification_km_summary.csv
echo "0.05" > patient_stratification_logrank_pvalue.txt
echo "CRAN_SURVIVAL_KAPLANMEIER:" > versions.yml
echo "    survival: 0.0.0" >> versions.yml
