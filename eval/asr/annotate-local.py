"""Propose reference spans locally, blinded to ASR hypotheses. Not human labels."""
import hashlib,json,subprocess,time,urllib.request
from pathlib import Path
base=Path.home()/'Library/Application Support/hushpen-comparison'
while not (base/'results-clean/summary.json').exists():time.sleep(5)
records=json.loads((base/'results-clean/corpus.json').read_text())
server=None;annotations={}
def request(path,payload=None):
    data=None if payload is None else json.dumps(payload).encode()
    req=urllib.request.Request('http://127.0.0.1:8791'+path,data=data,headers={'Content-Type':'application/json'})
    return json.load(urllib.request.urlopen(req,timeout=120))
try:
    server=subprocess.Popen(['/opt/homebrew/bin/llama-server','-m',str(Path.home()/'.cache/hushpen-eval/gemma-4-E4B_q4_0-it.gguf'),'--host','127.0.0.1','--port','8791','-ngl','99','-c','4096','--jinja'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(120):
        try:
            if request('/health').get('status')=='ok':break
        except Exception:
            if server.poll() is not None:raise RuntimeError('Local annotator startup failed')
            time.sleep(1)
    else:raise RuntimeError('Local annotator timeout')
    prompt='Extract exact verbatim spans from this German reference. Return only a JSON object with arrays names, numbers, terms. names: proper names of people, organizations and places. numbers: quantities, dates and numeric expressions; exclude indefinite articles on their own. terms: specialist scientific or technical terminology, excluding ordinary nouns and names. Copy spans exactly from the input, no explanation, no paraphrase. Use empty arrays when absent.'
    for record in records:
        ref=record['reference'];key=hashlib.sha256(ref.encode()).hexdigest()
        if key in annotations:continue
        answer=request('/v1/chat/completions',{'messages':[{'role':'system','content':prompt},{'role':'user','content':ref}],'temperature':0,'chat_template_kwargs':{'enable_thinking':False},'max_tokens':768,'response_format':{'type':'json_object'}})
        try:
            spans=json.loads(answer['choices'][0]['message']['content'])
            valid={category:list(dict.fromkeys(s for s in spans.get(category,[]) if isinstance(s,str) and s.strip() and s in ref)) for category in ['names','numbers','terms']}
            annotations[key]={'spans':valid,'status':'automatic_proposal_exact_substring_checked_not_human_verified'}
        except Exception:annotations[key]={'spans':{},'status':'annotation_failed'}
        (base/'proposed-reference-spans.json').write_text(json.dumps(annotations,ensure_ascii=False,indent=2))
    print('Local reference-span proposals finished:',len(annotations),'unique references; no hypotheses provided.',flush=True)
except Exception as error:
    print('Local annotation unavailable:',type(error).__name__,flush=True)
finally:
    if server:
        server.terminate()
        try:server.wait(timeout=20)
        except subprocess.TimeoutExpired:server.kill();server.wait()
    (base/'annotation-finished').touch()
