"""Sequential persistent-engine ASR evaluation. Private content never reaches logs."""
import argparse,hashlib,json,math,os,queue,re,statistics,subprocess,threading,time,unicodedata
from pathlib import Path
from collections import Counter


def words(text):
    return re.findall(r'[^\W_]+',unicodedata.normalize('NFC',text).casefold())


def distance(a,b):
    previous=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        current=[i]
        for j,y in enumerate(b,1):
            current.append(min(current[-1]+1,previous[j]+1,previous[j-1]+(x!=y)))
        previous=current
    return previous[-1]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('config',type=Path)
    parser.add_argument('--repetitions',type=int,default=3)
    args=parser.parse_args()
    config=json.loads(args.config.read_text())
    config['repetitions']=args.repetitions
    out=Path(config['output']).expanduser().resolve()
    # Refuse repository-local output, including ignored folders: private assets stay outside Git.
    repository=Path(__file__).resolve().parents[2]
    if out.is_relative_to(repository): raise ValueError('Output must be outside the repository')
    out.mkdir(parents=True,exist_ok=False);os.chmod(out,0o700)
    records=[]
    for corpus in config['corpora']:
        manifest=Path(corpus).expanduser().resolve()
        for item in json.loads(manifest.read_text()):
            item=dict(item);item['id']=str(len(records));audio=(manifest.parent/item['audio']).resolve()
            pcm=out/(item['id']+'.f32')
            subprocess.run(['ffmpeg','-nostdin','-v','quiet','-y','-i',str(audio),'-ac','1','-ar','16000','-f','f32le',str(pcm)],check=True)
            item.update(pcm=str(pcm),audio_s=pcm.stat().st_size/4/16000,pcm_sha256=hashlib.sha256(pcm.read_bytes()).hexdigest())
            records.append(item)
    (out/'corpus.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    rows=[];loads=[];failures=[]
    for repetition in range(args.repetitions):
        engines=config['engines'][repetition%len(config['engines']):]+config['engines'][:repetition%len(config['engines'])]
        for engine in engines:
            p=None;stop=threading.Event();peak=[0];resident=[0];sampler=None
            try:
                p=subprocess.Popen(engine['command'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,bufsize=1)
                responses=queue.Queue()
                def read_output(proc=p,responses=responses):
                    for line in proc.stdout:
                        try:
                            value=json.loads(line)
                            if isinstance(value,dict):responses.put(value)
                        except ValueError:pass # Never log unstructured model output.
                    responses.put({'error':'worker exited'})
                def sample(proc=p,stop=stop,peak=peak,resident=resident):
                    import psutil
                    while not stop.wait(.05):
                        try:
                            resident[0]=psutil.Process(proc.pid).memory_info().rss
                            peak[0]=max(peak[0],resident[0])
                        except psutil.Error:pass
                threading.Thread(target=read_output,daemon=True).start()
                sampler=threading.Thread(target=sample,daemon=True);sampler.start()
                def receive():
                    result=responses.get(timeout=300)
                    if 'error' in result:raise RuntimeError(result['error'])
                    return result
                ready=receive()
                if not ready.get('ready'):raise RuntimeError('worker not ready')
                loads.append({'engine':engine['name'],'repetition':repetition,**ready})
                for phase,subset in [('first_inference',records[:1]),('warm',records)]:
                    for record in subset:
                        p.stdin.write(json.dumps({'pcm':record['pcm']})+'\n');p.stdin.flush();result=receive()
                        a,b=words(record['reference']),words(result['text'])
                        digits_a=Counter(t for t in a if any(c.isdigit() for c in t))
                        digits_b=Counter(t for t in b if any(c.isdigit() for c in t))
                        numeric={'reference':sum(digits_a.values()),'hypothesis':sum(digits_b.values()),'correct':sum((digits_a & digits_b).values())}
                        entities={}
                        if record.get('annotations_status')=='verified':
                            normalized=' '+' '.join(b)+' '
                            for category in ['names','numbers','terms']:
                                spans=record.get(category,[])
                                entities[category]={'total':len(spans),'correct':sum((' '+' '.join(words(span))+' ') in normalized for span in spans)}
                        rows.append({'engine':engine['name'],'repetition':repetition,'phase':phase,'id':record['id'],
                            'source_kind':record['source_kind'],'reference_status':record.get('reference_status','synthetic_prompt'),
                            'audio_s':record['audio_s'],'reference_words':len(a),'edit_distance':distance(a,b),
                            'rss_bytes':resident[0],'entities':entities,'digit_tokens':numeric,**result})
                loads[-1]['sampled_peak_rss_bytes']=peak[0]
                print('Completed',engine['name'],'round',repetition+1,flush=True)
            except Exception as error:
                failures.append({'engine':engine['name'],'repetition':repetition,'error_type':type(error).__name__})
                print('Failed',engine['name'],type(error).__name__,flush=True)
            finally:
                if p:
                    try:p.stdin.close();p.wait(timeout=25)
                    except (subprocess.TimeoutExpired,BrokenPipeError):p.kill();p.wait()
                stop.set()
                if sampler:sampler.join()
                (out/'hypotheses.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
                (out/'loads.json').write_text(json.dumps(loads,indent=2))
                (out/'failures.json').write_text(json.dumps(failures,indent=2))
    summary=[]
    for engine in config['engines']:
        for kind in sorted({r['source_kind'] for r in records}):
            subset=[r for r in rows if r['engine']==engine['name'] and r['source_kind']==kind and r['phase']=='warm']
            if not subset:continue
            times=[r['stt_ms'] for r in subset];load=[r for r in loads if r['engine']==engine['name']]
            summary.append({'engine':engine['name'],'source_kind':kind,'n_runs':len(subset),
                'wer':sum(r['edit_distance'] for r in subset)/sum(r['reference_words'] for r in subset),
                'digit_tokens':{key:sum(r['digit_tokens'][key] for r in subset) for key in ['reference','hypothesis','correct']},
                'median_ms':statistics.median(times),'p95_ms':sorted(times)[math.ceil(.95*len(times))-1],
                'rtfx':sum(r['audio_s'] for r in subset)/(sum(times)/1000),
                'median_load_ms':statistics.median(r['load_ms'] for r in load),
                'sampled_peak_rss_mib':max(r.get('sampled_peak_rss_bytes',0) for r in load)/2**20})
    (out/'summary.json').write_text(json.dumps(summary,indent=2))
    (out/'config.json').write_text(json.dumps(config,indent=2))
    print('Saved aggregate summary; private hypotheses retained outside repository.',flush=True)

if __name__=='__main__':main()
