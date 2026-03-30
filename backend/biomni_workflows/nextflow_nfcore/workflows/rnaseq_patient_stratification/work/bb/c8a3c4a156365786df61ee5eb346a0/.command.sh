#!/bin/bash -ue
touch [patient_stratification]_km_fit.rds
touch [patient_stratification]_km_summary.csv
echo "0.05" > [patient_stratification]_logrank_pvalue.txt
echo "CRAN_SURVIVAL_KAPLANMEIER:" > versions.yml
echo "    survival: 0.0.0" >> versions.yml
