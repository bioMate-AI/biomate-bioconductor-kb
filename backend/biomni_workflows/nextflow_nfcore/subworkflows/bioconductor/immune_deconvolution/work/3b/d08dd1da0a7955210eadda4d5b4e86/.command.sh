#!/bin/bash -ue
touch run_immune_summary.csv
touch run_correlation_heatmap.pdf
echo "IMMUNEDECONV_SUMMARY:" > versions.yml
echo "    R: 4.4" >> versions.yml
