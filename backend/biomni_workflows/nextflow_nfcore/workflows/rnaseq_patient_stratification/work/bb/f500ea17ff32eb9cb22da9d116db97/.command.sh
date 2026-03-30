#!/bin/bash -ue
echo "sample,cluster" > [patient_stratification]_cluster_assignments.csv
echo "k,clusterConsensus" > [patient_stratification]_icl_scores.csv
echo "4" > [patient_stratification]_optimal_k.txt
echo "BIOC_CONSENSUSCLUSTERPLUS:" > versions.yml
echo "    consensusclusterplus: 0.0.0" >> versions.yml
