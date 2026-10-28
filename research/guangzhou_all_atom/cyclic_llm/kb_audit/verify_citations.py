"""Independent citation check for KB entries: query Crossref with the cited author/journal/year/volume/page and
compare the top hits' (year, volume, first page) with the cited triple. Verdicts: MATCH (year+volume+page agree),
PARTIAL (year+volume or page agree), NOMATCH, NOQUERY (no machine-checkable triple: guideline/historical/no locator).
Does not judge whether the paper SUPPORTS the KB claim — only that the cited bibliographic record exists as cited."""
import json, re, sys, time, urllib.parse, urllib.request
CITES = [  # (kb, entry_id, author, journal, year, volume, first_page)
 ("product.ADMET","herg","Aronov","Drug Discov Today",2005,"10","149"),
 ("product.ADMET","cyp*","Veith","Nat Biotechnol",2009,"27","1050"),
 ("product.ADMET","ames","Benigni","Chem Rev",2011,"111","2507"),
 ("product.ADMET","ames2","Xu","J Chem Inf Model",2012,"52","2840"),
 ("product.ADMET","dili","Chen","Drug Discov Today",2016,"21","648"),
 ("product.ADMET","dili2","Greene","Chem Res Toxicol",2010,"23","1215"),
 ("product.ADMET","bbb","Daina","ChemMedChem",2016,"11","1117"),
 ("product.ADMET","bbb2","Wager","ACS Chem Neurosci",2010,"1","435"),
 ("product.ADMET","pgp","Broccatelli","J Med Chem",2011,"54","1740"),
 ("product.ADMET","caco2","Hou","J Chem Inf Model",2007,"47","208"),
 ("product.ADMET","solubility","Delaney","J Chem Inf Comput Sci",2004,"44","1000"),
 ("product.ADMET","ppb","Votano","J Med Chem",2006,"49","7169"),
 ("product.ADMET","clearance","Di","Drug Metab Dispos",2013,"41","1975"),
 ("product.PHYSEXT","egan","Egan","J Med Chem",2000,"43","3867"),
 ("product.PHYSEXT","ghose","Ghose","J Comb Chem",1999,"1","55"),
 ("product.PHYSEXT","pfizer","Hughes","Bioorg Med Chem Lett",2008,"18","4872"),
 ("product.PHYSEXT","gsk","Gleeson","J Med Chem",2008,"51","817"),
 ("product.PHYSEXT","lead_like","Teague","Angew Chem Int Ed",1999,"38","3743"),
 ("product.PHYSEXT","qed","Bickerton","Nat Chem",2012,"4","90"),
 ("product.PHYSEXT","muegge","Muegge","J Med Chem",2001,"44","1841"),
 ("product.PHYSEXT","le","Hopkins","Nat Rev Drug Discov",2014,"13","105"),
 ("product.MODEXT","stapled","Walensky","J Med Chem",2014,"57","6275"),
 ("product.MODEXT","protac","Bekes","Nat Rev Drug Discov",2022,"21","181"),
 ("product.MODEXT","glue","Schreiber","Cell",2021,"184","3"),
 ("product.MODEXT","covalent","Singh","Nat Rev Drug Discov",2011,"10","307"),
 ("product.MODEXT","oligo","Roberts","Nat Rev Drug Discov",2020,"19","673"),
 ("product.MODEXT","adc","Beck","Nat Rev Drug Discov",2017,"16","315"),
 ("product.MODEXT","radioligand","Sgouros","Nat Rev Drug Discov",2020,"19","589"),
 ("product.PHARMEXT","kinase","Roskoski","Pharmacol Res",2016,"103","26"),
 ("product.PHARMEXT","gpcr","Congreve","Cell",2020,"181","81"),
 ("product.PHARMEXT","ppi","Arkin","Chem Biol",2014,"21","1102"),
 ("product.PHARMEXT","integrin","Kapp","Sci Rep",2017,"7","39805"),
 ("product.PHARMEXT","nr","Gronemeyer","Nat Rev Drug Discov",2004,"3","950"),
 ("product.PHARMEXT","brd","Filippakopoulos","Nat Rev Drug Discov",2014,"13","337"),
 ("product.PHARMEXT","ionch","Bagal","Nat Rev Drug Discov",2013,"12","35"),
 ("product.PHARMEXT","phosphatase","Barr","Future Med Chem",2010,"2","1563"),
 ("product.PHARMEXT","hdac","Falkenberg","Nat Rev Drug Discov",2014,"13","673"),
 ("product.PHARMEXT","protease","Schechter","Biochem Biophys Res Commun",1967,"27","157"),
 ("medchem.METAL","harding","Harding","Acta Crystallogr D",2006,"62","678"),
 ("medchem.METAL","metalpdb","Putignano","Nucleic Acids Res",2018,"46","D459"),
 ("medchem.METAL","checkmymetal","Zheng","Acta Crystallogr D",2017,"73","223"),
 ("medchem.METAL","limerz","Li","Chem Rev",2017,"117","1564"),
 ("medchem.METAL","duarte","Duarte","J Phys Chem B",2014,"118","4351"),
 ("medchem.PHARM","xiong","Xiong","Science",2002,"296","151"),
 ("medchem.PHARM","dong","Dong","Nat Struct Mol Biol",2014,"21","1091"),
 ("medchem.PHARM","clackson","Clackson","Science",1995,"267","383"),
 ("medchem.PHYS","lipinski","Lipinski","Adv Drug Deliv Rev",1997,"23","3"),
 ("medchem.PHYS","veber","Veber","J Med Chem",2002,"45","2615"),
 ("medchem.PHYS","doak","Doak","Chem Biol",2014,"21","1115"),
 ("medchem.PHYS","rezai","Rezai","J Am Chem Soc",2006,"128","14073"),
 ("medchem.PHYS","over","Over","Nat Chem Biol",2016,"12","1065"),
 ("medchem.PHYS","daina2017","Daina","Sci Rep",2017,"7","42717"),
 ("medchem.PHYS","xiong2021","Xiong","Nucleic Acids Res",2021,"49","W5"),
 ("medchem.MOD","driggers","Driggers","Nat Rev Drug Discov",2008,"7","608"),
 ("medchem.MOD","biron","Biron","Angew Chem Int Ed",2008,"47","2595"),
 ("medchem.MOD","chatterjee","Chatterjee","Acc Chem Res",2008,"41","1331"),
 ("experience.sar","kapp?","Kapp","Sci Rep",2017,"7","39805"),
]
def q(a,j,y,v,p):
    url="https://api.crossref.org/works?"+urllib.parse.urlencode({"query.bibliographic":f"{a} {j} {y} {v} {p}","rows":5,"select":"DOI,title,issued,volume,page,container-title,author"})
    req=urllib.request.Request(url,headers={"User-Agent":"kb-audit/1.0 (mailto:xiaoni5122@gmail.com)"})
    return json.load(urllib.request.urlopen(req,timeout=30))["message"]["items"]
out=[]
for kb,i,a,j,y,v,p in CITES:
    try: items=q(a,j,y,v,p)
    except Exception as e: out.append(dict(kb=kb,id=i,cited=f"{a} {j} {y};{v}:{p}",verdict="ERROR",note=str(e)[:80])); continue
    best=None
    for it in items:
        yr=(it.get("issued",{}).get("date-parts") or [[None]])[0][0]; vol=str(it.get("volume","")); pg=str(it.get("page","")).split("-")[0]
        au=" ".join(x.get("family","") for x in it.get("author",[])[:3]).lower()
        s=(yr==y)+(vol==v)+(pg==p)+(a.lower() in au)
        if best is None or s>best[0]: best=(s,yr,vol,pg,(it.get("title") or [""])[0][:90],it.get("DOI"))
    verdict="MATCH" if best and best[0]>=4 else "MATCH_3of4" if best and best[0]==3 else "PARTIAL" if best and best[0]==2 else "NOMATCH"
    out.append(dict(kb=kb,id=i,cited=f"{a} {j} {y};{v}:{p}",verdict=verdict,found=best))
    time.sleep(0.15)
json.dump(out,open("citation_check.json","w"),indent=1)
import collections
print(collections.Counter(o["verdict"] for o in out))
for o in out:
    if o["verdict"] not in("MATCH",): print(o["kb"],o["id"],o["cited"],o["verdict"],o.get("found"),o.get("note"))
