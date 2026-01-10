#!/usr/bin/awk -f

# Take an alignment as string with gaps and
# fill the dictionary with a key (qpos,tpos) for each aligned residue pair.
# Example: ('ABC--', '-BCDE', 0, 0, {}) -> {(2,2), (3,3)}
function aln2pairs(qstart, tstart, qaln, taln, pairs) {
  split(qaln, qaln_arr, "")
  split(taln, taln_arr, "")
  qpos = qstart
  tpos = tstart
  for (i=1; i <= length(qaln); i++) {
    q_is_letter = (qaln_arr[i] != "-") && (qaln_arr[i] != "/")
    t_is_letter = (taln_arr[i] != "-") && (taln_arr[i] != "/")
    if (q_is_letter && t_is_letter){
      key = qpos "," tpos
      pairs[key] = 1
      }
    if (q_is_letter){
      qpos++
    }
    if (t_is_letter){
      tpos++
    }
  }
}

function sensitivity(pairs_ref, pairs_test){
  all_pairs = 0
  found_pairs = 0
  for (pair_ref in pairs_ref){
    if (pair_ref in pairs_test){
      found_pairs++
      }
    all_pairs++
  }
  return found_pairs / all_pairs
}

function precision(pairs_ref, pairs_test){
  all_pairs = 0
  correct_pairs = 0
  for (pair_test in pairs_test){
    if (pair_test in pairs_ref){
      correct_pairs++
      }
    all_pairs++
  }
  return correct_pairs / all_pairs
}

# MAIN
{aln2pairs(1, 1, $4, $5, pairs_ref);
 aln2pairs($6, $7, $8, $9, pairs_test);
 printf "%s %.3f %.3f\n",
           $3, sensitivity(pairs_ref, pairs_test), precision(pairs_ref, pairs_test);
 delete pairs_ref; delete pairs_test;}

