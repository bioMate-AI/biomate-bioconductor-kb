#!/bin/bash -ue
echo "sample,cluster" > patient_stratification_cluster_assignments.csv
echo "k,clusterConsensus" > patient_stratification_icl_scores.csv
echo "4" > patient_stratification_optimal_k.txt
echo "BIOC_CONSENSUSCLUSTERPLUS:" > versions.yml
echo "    consensusclusterplus: 0.0.0" >> versions.yml
