#!/bin/bash -ue
touch run_cell_fractions.csv
touch run_deconvolution_plot.pdf
touch run_deconvolution.rds
echo "BIOC_DECONRNASEQ:" > versions.yml
echo "    DeconRNASeq: 1.46.0" >> versions.yml
echo "    R: 4.4" >> versions.yml
