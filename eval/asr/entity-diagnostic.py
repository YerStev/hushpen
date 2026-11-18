"""Exact span-retention diagnostics for automatically proposed local labels."""
import hashlib,json
from pathlib import Path
from run import words
base=Path.home()/'Library/Application Support/hushpen-comparison'
records=json.loads((base/'results-clean/corpus.json').read_text());annotations=json.loads((base/'proposed-reference-spans.json').read_text());refs={r['id']:r for r in records}
rows=json.loads((base/'results-clean/hypotheses.json').read_text())
if (base/'results-native/hypotheses.json').exists():rows+=json.loads((base/'results-native/hypotheses.json').read_text())
output=[]
for engine in sorted({r['engine'] for r in rows}):
    for kind in sorted({r['source_kind'] for r in rows}):
        subset=[r for r in rows if r['engine']==engine and r['phase']=='warm' and r['source_kind']==kind and r['repetition']==0]
        if not subset:continue
        scores={c:{'total':0,'retained':0} for c in ['names','numbers','terms']}
        for row in subset:
            reference=refs[row['id']]['reference'];key=hashlib.sha256(reference.encode()).hexdigest();spans=annotations.get(key,{}).get('spans',{});hyp=' '+' '.join(words(row['text']))+' '
            for category in scores:
                for span in spans.get(category,[]):
                    scores[category]['total']+=1
                    scores[category]['retained']+=int((' '+' '.join(words(span))+' ') in hyp)
        output.append({'engine':engine,'source_kind':kind,'n_clips':len(subset),'span_retention':scores})
result={'method':'Gemma 4 E4B Q4_0 local, greedy, thinking off; reference-only proposals, exact-substring validated; not human verified. First ASR repetition only. Exact normalized span presence, not semantic numeric correctness or hallucinated-entity precision.','results':output}
(base/'entity-diagnostic.json').write_text(json.dumps(result,indent=2))
for row in output:
    if row['source_kind']=='public_fleurs':print(row['engine'],row['span_retention'])
