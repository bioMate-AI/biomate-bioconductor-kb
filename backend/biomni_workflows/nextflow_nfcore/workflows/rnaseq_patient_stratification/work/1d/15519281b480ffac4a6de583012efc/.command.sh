#!/bin/bash -ue
touch [patient_stratification]_cox_model.rds
echo "term,estimate,std.error,statistic,p.value,conf.low,conf.high" > [patient_stratification]_cox_results.csv
echo "CRAN_SURVIVAL_COX:" > versions.yml
echo "    survival: 0.0.0" >> versions.yml
echo "    broom: 0.0.0" >> versions.yml
