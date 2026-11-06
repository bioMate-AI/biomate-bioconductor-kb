"""Independent re-verification of Kapp 2017 matrix.csv cells against the table JPEGs.
READING_* below was typed from a fresh visual read of the PMC table images (src_raw/kapp2017_srep39805-t{1,2}.jpg),
as image crops viewed at full resolution. G = '> 10000' (censored)."""
import pandas as pd, random, json
G = ">10000"
I = ["avb3","avb5","avb6","avb8","a5b1","aIIbb3"]
T = {
"Echistatin":["0.46","1.4","13.7","12.8","0.57","0.90"],
"RGD":["89","440",G,G,"335",G],"RGDS":["45","433",G,G,"181",G],"GRGD":["55","580",G,G,"137",G],
"GRGDS":["28","260","1480",G,"77",G],"GRGDSP":["13.7","167","693",G,"51",G],"GRGDSPK":["12.2","201","1030",G,"66",G],
"GRGDNP":["45","506",G,G,"34",G],"GRGDTP":["28","423",G,G,"84",G],
"c(RGDfV)":["1.54","250","49",G,"200",G],"Cilengitide":["0.61","8.4","2050","2350","14.9","5400"],
"c(RGDfK)":["2.25","340","55","5200","141",G],"c(RGDyK)":["3.8","503","86",G,"236",G],"c(RGDfC)":["6.3","433","121",G,"215",G],
"sn243":["0.65","199",G,G,"108",G],"RGD-4C":["8.3","46","380",G,"244",G],"RGD10 (RGD-2C)":["10.3","102","278",G,"133",G],
"NC100717":["1.1","16.7",G,G,"820",G],"c(phgisoDGRk)":[G,G,"18","77","9.43",G],"44b":[G,G,"433","37","2.3",G],
"ATN161":[G,G,"3133",G,"4.2",G],"JSM6427":[G,G,"23","8.2","2.5",G],"RTDLDSLRT":["6233",G,"29.5","320",G,G],
"A20FMDV2":[G,G,"0.93","45",G,G],"Mol11":["13.2","530","1.32","18.5","3020",G],
"c(FRGDLAFp(NMe)K)":["1200",G,"0.28","24","73",G],
"Eptifibatide":[G,G,G,G,G,"2.44"],"Tirofiban":[G,G,G,G,G,"1.3"],"GR144053":[G,G,G,G,G,"18"],
"F-Galacto-c(RGDfK)":["8.2","310","840",G,"41",G],"(Ga)NOPO*-c(RGDfK)":["1.1","299","255",G,"25",G],
"c(RGDfK)-Peg-MPA":["15","390","422",G,"201",G],"Flucilatide":["2.3","36",G,G,"1170",G],
"c(phgisoDGRk)-Peg-MPA":[G,G,"52",G,"31",G]}
m = pd.read_csv("../integrin_selectivity/matrix.csv"); k = m[m.source == "kapp2017"]
assert len(k) == 204
obs = {(r.ligand_id, r.integrin): (r.ic50_nM, r.censor) for r in k.itertuples()}
bad = []; allc = []
for lig, vals in T.items():
    for integ, v in zip(I, vals):
        o = obs.get((lig, integ))
        if o is None: bad.append((f"{lig}|{integ}", "missing in matrix.csv")); continue
        cens = v == G; exp = (10000.0 if cens else float(v), ">" if cens else "=")
        allc.append(f"{lig}|{integ}")
        if abs(o[0] - exp[0]) > 1e-9 or o[1] != exp[1]: bad.append((f"{lig}|{integ}", f"matrix={o} image={exp}"))
random.seed(20261025); sample = random.sample(allc, 40)
res = {"n_cells_image_reading": len(allc), "n_matrix_kapp_cells": len(k), "sample40": sample,
       "mismatches_in_sample40": [b for b in bad if b[0] in sample], "mismatches_all_cells": bad}
json.dump(res, open("data/kapp_reverification.json", "w"), indent=1); print(json.dumps({k_: res[k_] for k_ in ["n_cells_image_reading","mismatches_in_sample40","mismatches_all_cells"]}, indent=1))
