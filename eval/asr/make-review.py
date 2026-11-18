"""Create a private offline reference/target review form; no network requests."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('manifest',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
if a.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):raise ValueError('Keep references outside the repository')
records=json.loads(a.manifest.read_text())
for r in records:
    r['audio']=str((a.manifest.resolve().parent/r['audio']).resolve())
    r['audio_uri']=Path(r['audio']).as_uri()
data=json.dumps(records,ensure_ascii=False).replace('</','<\\/')
html='''<!doctype html><meta charset="utf-8"><title>Private reference review</title>
<style>body{font:17px system-ui;max-width:950px;margin:40px auto;background:#fafafa;color:#17202a}section{background:white;padding:24px;margin:20px 0;border:1px solid #ddd;border-radius:12px}textarea{width:100%;min-height:110px;font:inherit}input[type=text]{display:block;width:95%;margin:6px 0 16px;padding:8px}audio{width:100%;margin:12px 0}button{font:inherit;padding:15px}label{display:block;margin:10px 0}</style>
<h1>Private reference review</h1><p>Play each recording and correct the verbatim reference, including fillers and abandoned phrases. The intended cleaned text is a different reference. Everything stays in this local file/browser; nothing is uploaded.</p>
<p>Optionally annotate names, numbers and specialist terms as exact spans from the corrected reference, separated by |. Review these before inspecting recognition output. Check each confirmation only after listening.</p><main></main><button id="save">Export reviewed manifest</button>
<script>const records=RECORDS;const forms=[];
records.forEach((r,i)=>{const s=document.createElement('section');const h=document.createElement('h2');h.textContent='Recording '+(i+1);s.append(h);const audio=document.createElement('audio');audio.controls=true;audio.src=r.audio_uri;s.append(audio);const text=document.createElement('textarea');text.value=r.reference;s.append(text);const fields={};for(const name of ['names','numbers','terms']){const label=document.createElement('label');label.textContent=name;const input=document.createElement('input');input.type='text';label.append(input);s.append(label);fields[name]=input}const label=document.createElement('label');const check=document.createElement('input');check.type='checkbox';label.append(check,document.createTextNode(' I listened and verified this reference and the supplied target spans.'));s.append(label);document.querySelector('main').append(s);forms.push({text,fields,check})});
document.querySelector('#save').onclick=()=>{if(forms.some(f=>!f.check.checked)){alert('Verify every recording before export.');return}const output=records.map((r,i)=>{const {audio_uri,...rest}=r;const f=forms[i];const annotations={};for(const k of ['names','numbers','terms'])annotations[k]=f.fields[k].value.split('|').map(v=>v.trim()).filter(Boolean);return {...rest,reference:f.text.value,reference_status:'manually_verified',annotations_status:'verified',...annotations}});const link=document.createElement('a');link.href=URL.createObjectURL(new Blob([JSON.stringify(output,null,2)],{type:'application/json'}));link.download='reviewed-manifest.json';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000)};</script>'''.replace('RECORDS',data)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(html)
print('Created private offline review form; no text printed.')
