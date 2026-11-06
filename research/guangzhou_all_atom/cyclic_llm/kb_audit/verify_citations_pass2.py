"""Pass 2: for citations flagged PARTIAL/NOMATCH in pass 1, search Crossref by author + distinctive TITLE words
(the cited triple was not found by bibliographic query). Report top hits; a human-readable verdict is written in the audit doc."""
import json, urllib.parse, urllib.request, time
Q=[("Hou 2007 JCIM 47:208 (caco2)","Hou ADME evaluation in drug discovery 7 prediction of oral absorption Caco-2"),
   ("Di 2013 DMD 41:1975 (clearance)","Di Kerns Carter clearance human hepatocytes microsomes drug metabolism and disposition 2013"),
   ("Hughes 2008 BMCL 18:4872 (Pfizer 3/75)","Hughes Physicochemical drug properties associated with in vivo toxicological outcomes"),
   ("Kapp 2017 Sci Rep 7:39805","Kapp comprehensive evaluation of the activity and selectivity profile of ligands for RGD-binding integrins"),
   ("Bagal 2013 NRD 12:35 (ion channel)","Bagal ion channels as therapeutic targets drug discovery perspective"),
   ("Schechter&Berger 1967 BBRC 27:157","Schechter Berger On the size of the active site in proteases I papain"),
   ("Biron 2008 Angew 47:2595","Biron Improving oral bioavailability of peptides by multiple N-methylation somatostatin analogues"),
   ("Ghose 1999 J Comb Chem 1:55","Ghose Viswanadhan Wendoloski knowledge-based approach in designing combinatorial medicinal chemistry libraries drug discovery"),
   ("Hughes alt: NRD ion channel","Nature Reviews Drug Discovery 2013 12 35 ion channel")]
for label,qs in Q:
    url="https://api.crossref.org/works?"+urllib.parse.urlencode({"query.bibliographic":qs,"rows":3,"select":"DOI,title,issued,volume,page,article-number,container-title,author"})
    r=urllib.request.Request(url,headers={"User-Agent":"kb-audit/1.0 (mailto:xiaoni5122@gmail.com)"})
    try: items=json.load(urllib.request.urlopen(r,timeout=30))["message"]["items"]
    except Exception as e: print(label,"ERROR",e); continue
    print("\n##",label)
    for it in items[:3]:
        yr=(it.get("issued",{}).get("date-parts") or [[None]])[0][0]; au=", ".join(x.get("family","") for x in it.get("author",[])[:3])
        print("  ",yr,(it.get("container-title") or [""])[0][:40],"vol",it.get("volume"),"p",it.get("page") or it.get("article-number"),"|",(it.get("title") or [""])[0][:85],"|",au,"|",it.get("DOI"))
    time.sleep(0.2)
