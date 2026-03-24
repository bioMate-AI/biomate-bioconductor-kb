#!/bin/bash -ue
touch run_trajectory_pseudotime.csv
touch run_trajectory_plot.png
touch run_monocle3_cds.rds
echo "MONOCLE3_TRAJECTORY:" > versions.yml
echo "    monocle3: 1.3.4" >> versions.yml
echo "    R: 4.4" >> versions.yml
