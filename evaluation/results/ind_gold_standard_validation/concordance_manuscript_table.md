## Table 4. BioMate ADMET-AI Concordance with Known Reference Compound Safety Profiles

All values are from ADMET-AI Chemprop-RDKit predictions vs. published measured data
(n=39 reference compounds; sources: Redfern 2003, DILIrank, Hansen 2009, ChEMBL).

### 4a. Endpoint-level summary

| Endpoint | n | TP | TN | FP | FN | Sens | Spec | Acc | Bal.Acc | MCC |
|----------|---|-----|-----|-----|-----|------|------|-----|---------|-----|
| hERG | 39 | 10 | 14 | 14 | 1 | 0.909 | 0.500 | 0.615 | 0.705 | 0.378 |
| DILI | 39 | 13 | 6 | 9 | 11 | 0.542 | 0.400 | 0.487 | 0.471 | -0.057 |
| Ames | 39 | 3 | 28 | 7 | 1 | 0.750 | 0.800 | 0.795 | 0.775 | 0.382 |

*Sensitivity = TP/(TP+FN); Specificity = TN/(TN+FP); MCC = Matthews Correlation Coefficient.*
*Classification threshold: p ≥ 0.50 for all endpoints.*

### 4b. Compound-level predictions

| Compound | Status | hERG gold | hERG pred | hERG | DILI gold | DILI pred | DILI | Ames gold | Ames pred | Ames |
|----------|--------|-----------|-----------|------|-----------|-----------|------|-----------|-----------|------|
| Acetaminophen | approved | − | 0.10 | TN | + | 0.58 | TP | − | 0.30 | TN |
| Amiodarone | approved | + | 0.96 | TP | + | 0.59 | TP | − | 0.40 | TN |
| Astemizole | withdrawn_1999 | + | 0.99 | TP | + | 0.35 | FN | − | 0.25 | TN |
| Atorvastatin | approved | − | 0.77 | FP | − | 0.90 | FP | − | 0.09 | TN |
| Caffeine | approved | − | 0.05 | TN | − | 0.93 | FP | − | 0.11 | TN |
| Carbamazepine | approved_REMS | − | 0.28 | TN | + | 0.70 | TP | − | 0.23 | TN |
| Cisapride | withdrawn_2000 | + | 0.97 | TP | + | 0.62 | TP | − | 0.47 | TN |
| Clarithromycin | approved | − | 0.80 | FP | + | 0.50 | TP | − | 0.58 | FP |
| Clozapine | approved_REMS | + | 0.97 | TP | + | 0.46 | FN | − | 0.32 | TN |
| Diclofenac | approved | − | 0.18 | TN | + | 0.88 | TP | − | 0.06 | TN |
| Digoxin | approved | − | 0.85 | FP | − | 0.20 | TN | − | 0.67 | FP |
| Dofetilide | approved_restricted_REMS | + | 0.92 | TP | − | 0.72 | FP | − | 0.22 | TN |
| Erythromycin | approved | + | 0.48 | FN | + | 0.33 | FN | − | 0.50 | FP |
| Fluoxetine | approved | + | 0.89 | TP | − | 0.22 | TN | − | 0.05 | TN |
| Haloperidol | approved | + | 0.95 | TP | + | 0.15 | FN | − | 0.11 | TN |
| Ibuprofen | approved | − | 0.13 | TN | − | 0.43 | TN | − | 0.01 | TN |
| Isoniazid | approved | − | 0.31 | TN | + | 0.77 | TP | + | 0.71 | TP |
| Ketoconazole | withdrawn_oral_2013 | − | 0.96 | FP | + | 0.93 | TP | − | 0.39 | TN |
| Metformin | approved | − | 0.04 | TN | − | 0.00 | TN | − | 0.11 | TN |
| Methotrexate | approved | − | 0.06 | TN | + | 0.97 | TP | + | 0.29 | FN |
| Metoprolol | approved | − | 0.58 | FP | − | 0.10 | TN | − | 0.07 | TN |
| Midazolam | approved | − | 0.80 | FP | − | 0.85 | FP | − | 0.37 | TN |
| Mitomycin_C | approved_oncology | − | 0.16 | TN | + | 0.48 | FN | + | 0.90 | TP |
| Nifedipine | approved | − | 0.25 | TN | − | 0.87 | FP | − | 0.21 | TN |
| Nitrofurantoin | approved | − | 0.04 | TN | + | 0.97 | TP | + | 0.99 | TP |
| Omeprazole | approved | − | 0.76 | FP | − | 0.92 | FP | − | 0.74 | FP |
| Phenytoin | approved | − | 0.02 | TN | + | 0.93 | TP | − | 0.15 | TN |
| Propranolol | approved | − | 0.78 | FP | − | 0.19 | TN | − | 0.18 | TN |
| Quinidine | approved | + | 0.90 | TP | + | 0.29 | FN | − | 0.39 | TN |
| Rifampin | approved | − | 0.80 | FP | + | 0.96 | TP | − | 0.85 | FP |
| Rosuvastatin | approved | − | 0.56 | FP | − | 0.80 | FP | − | 0.10 | TN |
| Sildenafil | approved | − | 0.77 | FP | − | 0.93 | FP | − | 0.53 | FP |
| Simvastatin | approved | − | 0.72 | FP | + | 0.22 | FN | − | 0.54 | FP |
| Tamoxifen | approved | − | 0.92 | FP | + | 0.47 | FN | − | 0.23 | TN |
| Terfenadine | withdrawn_1998 | + | 0.99 | TP | + | 0.06 | FN | − | 0.01 | TN |
| Troglitazone | withdrawn_2000 | − | 0.53 | FP | + | 0.83 | TP | − | 0.19 | TN |
| Valproic_Acid | approved_REMS | − | 0.01 | TN | + | 0.28 | FN | − | 0.03 | TN |
| Verapamil | approved | + | 0.97 | TP | + | 0.34 | FN | − | 0.12 | TN |
| Warfarin | approved | − | 0.02 | TN | − | 0.55 | FP | − | 0.05 | TN |

*gold: +/− = measured positive/negative; pred: ADMET-AI probability; TP/TN/FP/FN.*