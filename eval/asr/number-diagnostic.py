"""Restricted number-format sensitivity diagnostic; not semantic verification."""
import json,re
from pathlib import Path
from num2words import num2words
from run import words,distance
base=Path.home()/'Library/Application Support/hushpen-comparison';records=json.loads((base/'results-clean/corpus.json').read_text());refs={r['id']:r['reference'] for r in records}
rows=json.loads((base/'results-clean/hypotheses.json').read_text())
if (base/'results-native/hypotheses.json').exists():rows+=json.loads((base/'results-native/hypotheses.json').read_text())
def normalize_pair(reference,hypothesis):
    a,b=words(reference),words(hypothesis);forms={}
    for token in set(a+b):
        if not re.fullmatch(r'[1-9][0-9]{0,11}',token) or int(token)<2:continue
        value=int(token)
        try:
            variants=[num2words(value,lang='de'),num2words(value,lang='de',to='ordinal')]
            for variant in list(variants):
                if variant.startswith('ein') and ('hundert' in variant or 'tausend' in variant):variants.append(variant[3:])
            for variant in variants:forms[tuple(words(variant))]=token
        except Exception:pass
    def apply(tokens):
        result=[];i=0
        while i<len(tokens):
            found=False
            for form,value in sorted(forms.items(),key=lambda item:-len(item[0])):
                if tokens[i:i+len(form)]==list(form):result.append(value);i+=len(form);found=True;break
            if not found:result.append(tokens[i]);i+=1
        return result
    return apply(a),apply(b)
output=[]
for engine in sorted({r['engine'] for r in rows}):
    for kind in sorted({r['source_kind'] for r in rows}):
        subset=[r for r in rows if r['engine']==engine and r['phase']=='warm' and r['source_kind']==kind and r['repetition']==0]
        if not subset:continue
        pairs=[normalize_pair(refs[r['id']],r['text']) for r in subset]
        output.append({'engine':engine,'source_kind':kind,'n_clips':len(subset),'reference_words':sum(len(a) for a,b in pairs),'edit_distance':sum(distance(a,b) for a,b in pairs),'wer':sum(distance(a,b) for a,b in pairs)/sum(len(a) for a,b in pairs)})
(base/'number-format-diagnostic.json').write_text(json.dumps({'method':'Reference/hypothesis digit values >=2 define canonical German cardinal/ordinal word variants; exact token-span replacement only. No general numeric semantic verification, no numeric accuracy claim. First repetition only.','results':output},indent=2))
for row in output:
    if row['source_kind']=='public_fleurs':print(row['engine'],round(row['wer']*100,2))
