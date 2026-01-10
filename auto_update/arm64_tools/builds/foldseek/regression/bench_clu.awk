#!/usr/bin/awk -f
BEGIN{OFS="\t";
      print "NAME","SCOP","TP","FP","FAMCNT","SFAMCNT","FOLDCNT";
}
FNR==NR{
        id2fam[$1]=$2;
        famCnt[$2]++;
        gsub(/\.[0-9]+$/,"",$2);
        id2sfam[$1]=$2;
        sfamCnt[$2]++;
        gsub(/\.[0-9]+$/,"",$2);
        id2fold[$1]=$2;
        foldCnt[$2]++;
        next }

!($1 in repseq){repseq[$1]=1;}
id2fold[$1] != id2fold[$2] {foundFp[$1]++; next}
id2fold[$1] == id2fold[$2] {foundTp[$1]++; next}

END{
   for(i in repseq){
        fpCnt = (foundFp[i] == "") ? 0 : foundFp[i];
        tpCnt = (foundTp[i] == "") ? 0 : foundTp[i];
        print i,id2fam[i],tpCnt,fpCnt,famCnt[id2fam[i]],sfamCnt[id2sfam[i]],foldCnt[id2fold[i]];
   }
}
