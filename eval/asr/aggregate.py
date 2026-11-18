"""Export aggregates only. Private references and hypotheses never enter reports."""
import argparse,json,statistics,struct,zipfile
from pathlib import Path
import numpy as np
from run import words
p=argparse.ArgumentParser();p.add_argument('state',type=Path);p.add_argument('report',type=Path);p.add_argument('aggregate_json',type=Path);a=p.parse_args();base=a.state.expanduser()
main=base/'results-clean';native=base/'results-native'
assert (main/'summary.json').exists() and (native/'summary.json').exists(), 'Wait for both runs'
assert json.loads((main/'failures.json').read_text())==[]
assert json.loads((native/'failures.json').read_text())==[]
corpus=json.loads((main/'corpus.json').read_text());other=json.loads((native/'corpus.json').read_text())
assert [(r['id'],r['pcm_sha256']) for r in corpus]==[(r['id'],r['pcm_sha256']) for r in other], 'PCM changed'
rows=json.loads((main/'hypotheses.json').read_text())+json.loads((native/'hypotheses.json').read_text())
summary=json.loads((main/'summary.json').read_text())+json.loads((native/'summary.json').read_text())
loads=json.loads((main/'loads.json').read_text())+json.loads((native/'loads.json').read_text())
labels={'voz-old':'Voz 0.1.0 / SDK 3.5.0','voz-new':'Voz 0.5.0 / SDK 4.3.0','parakeet-v3':'Direct Parakeet V3 Q4','whisper-turbo':'Whisper turbo FP16','whisper-large':'Whisper large-v3 Q4','cohere':'Cohere adapted export (exploratory)','cohere-native':'Cohere native MLX-Audio Q4','whisper-german':'Whisper turbo German, encoder Q4','whisper-turbo-q4':'Whisper turbo control, matched encoder Q4'}
order=['voz-old','voz-new','parakeet-v3','whisper-turbo','whisper-large','whisper-german','whisper-turbo-q4','cohere-native']
public={r['engine']:r for r in summary if r['source_kind']=='public_fleurs'}
corpus_stats={}
for kind in sorted({r['source_kind'] for r in corpus}):
    subset=[r for r in corpus if r['source_kind']==kind]
    corpus_stats[kind]={'clips':len(subset),'unique_reference_texts':len({r['reference'] for r in subset}),'reference_words':sum(len(words(r['reference'])) for r in subset),'seconds':sum(r['audio_s'] for r in subset)}
# Repeated latency runs are not independent accuracy observations.
first={(r['engine'],r['id']):r for r in rows if r['phase']=='warm' and r['source_kind']=='public_fleurs' and r['repetition']==0}
ids=[r['id'] for r in corpus if r['source_kind']=='public_fleurs'];rng=np.random.default_rng(0);indices=rng.integers(0,len(ids),size=(10000,len(ids)));intervals=[]
for left,right in [('voz-new','voz-old'),('whisper-german','whisper-turbo-q4'),('whisper-large','whisper-turbo')]:
    errors=np.array([first[left,i]['edit_distance']-first[right,i]['edit_distance'] for i in ids]);counts=np.array([first[left,i]['reference_words'] for i in ids]);deltas=100*errors[indices].sum(axis=1)/counts[indices].sum(axis=1)
    intervals.append({'comparison':left+' minus '+right,'delta_percentage_points':100*errors.sum()/counts.sum(),'paired_clip_bootstrap_95_interval_pp':np.quantile(deltas,[.025,.975]).tolist(),'draws':10000,'seed':0})
models=json.loads((base/'model-provenance.json').read_text());models.append(json.loads((base/'model-provenance-native.json').read_text()))
public_models=[]
for m in models:
    entry={k:m[k] for k in ['name','family','repository','revision','conversion'] if k in m}
    directory=Path(m['path']);config=json.loads((directory/'config.json').read_text())
    entry['quantization']=config.get('quantization',config.get('quantization_config','not declared'))
    scales=[];weight_files={}
    for weight in [*directory.glob('*.safetensors'),*directory.glob('*.npz')]:
        weight_files[weight.name]={'bytes':weight.stat().st_size,'sha256':m['files_sha256'][weight.name]}
        if weight.suffix=='.npz':
            with zipfile.ZipFile(weight) as archive:scales.extend(name[:-4] for name in archive.namelist() if name.endswith('.scales.npy'))
        else:
            with weight.open('rb') as inp:length=struct.unpack('<Q',inp.read(8))[0];header=json.loads(inp.read(length))
            scales.extend(name for name in header if name.endswith('.scales'))
    entry['quantized_modules_by_root']={root:sum(name.split('.')[0]==root for name in scales) for root in sorted({name.split('.')[0] for name in scales})}
    entry['weight_files']=weight_files;public_models.append(entry)
entity=json.loads((base/'entity-diagnostic.json').read_text())
number_diagnostic=json.loads((base/'number-format-diagnostic.json').read_text())
result={'entity_diagnostic':entity,'number_format_diagnostic':number_diagnostic,'date':'2026-11-10','hardware':{'chip':'Apple M1 Pro','cpu_cores':8,'ram_gib':16,'macos':'26.6.2','swift':'6.4'},'runtime':{'mlx':'0.32.4','mlx_audio':'0.6.5','mlx_whisper':'0.4.3'},'corpora':corpus_stats,'repetitions':2,'models':public_models,'summary':summary,'bootstrap':intervals,'excluded_preparation_run':True,'adapted_cohere_exploratory_only':True,'native_pcm_identical_to_main':True}
a.aggregate_json.write_text(json.dumps(result,indent=2)+'\n')
lines=['# ASR results on this Mac, 2026-11-10','','Two sequential rounds per model; no cleanup, vocabulary hints or app UI. The hushpen service was stopped during timing and restored afterward. Setup/downloads finished before timed runs. An earlier preparation run overlapped setup and is excluded. The native Cohere export was tested in a separate follow-up, with identical PCM hashes and the same two-round protocol.','','M1 Pro, 8 CPU cores, 16 GiB RAM, macOS 26.6.2, Swift 6.4; AC power. SDKs 3.5.0 / 4.3.0; MLX 0.32.4, MLX-Audio 0.6.5, mlx-whisper 0.4.3. Core ML was configured for CPU + Neural Engine; MLX used Metal. Layer utilization was not profiled.','','## Published German references','','First 20 German FLEURS test rows, selected before inference: 450 reference words, 20 distinct texts. These are published benchmark references, not manually re-audited here. Each clip ran twice; repetitions do not double the accuracy sample size. WER is strict NFC/casefold/tokenized edit distance with no number equivalence. Higher RTFx is faster.','','| Model / tested export | WER | Warm median | Warm p95 | RTFx | Model load | Sampled peak RSS |','| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
for name in order:
    r=public[name];lines.append(f"| {labels[name]} | {r['wer']*100:.2f}% | {r['median_ms']:.0f} ms | {r['p95_ms']:.0f} ms | {r['rtfx']:.1f}× | {r['median_load_ms']:.0f} ms | {r['sampled_peak_rss_mib']:.0f} MiB |")
lines+=['','Load is a fresh-process model initialization after preparation of Core ML caches, not a cold-filesystem or first-install compilation measurement. Python imports outside the model loader are recorded separately locally. RSS is sampled every 50 ms and excludes some driver/accelerator allocations; it is not total unified-memory use. Do not add RSS and MLX allocation figures together.','','## Personal and synthetic material','','The six personal clips have 169 reference words; all references were marked read_prompt_unverified. Their WER is provisional. The 30 synthetic clips have 1,150 reference words and only 15 distinct texts (clean/noisy pairs); they are a separate stress test, not human dictation accuracy.','','| Model | Personal WER, unverified references | Synthetic WER |','| --- | ---: | ---: |']
for name in order:
    human=next(r for r in summary if r['engine']==name and r['source_kind']=='human');synthetic=next(r for r in summary if r['engine']==name and r['source_kind']=='synthetic');lines.append(f"| {labels[name]} | {100*human['wer']:.2f}% | {100*synthetic['wer']:.2f}% |")
lines+=['','## First inference and resident memory','','First inference uses the same first personal clip for every engine; the timed warm pass follows it. Peak MLX allocation is an allocator diagnostic, not total process or machine memory.','','| Model | First inference, median | Warm RSS, median on FLEURS | Peak MLX allocation |','| --- | ---: | ---: | ---: |']
for name in order:
    cold=[r['stt_ms'] for r in rows if r['engine']==name and r['phase']=='first_inference'];warm=[r['rss_bytes']/2**20 for r in rows if r['engine']==name and r['phase']=='warm' and r['source_kind']=='public_fleurs'];peak=max((r.get('mlx_peak_bytes',0) for r in rows if r['engine']==name),default=0);allocated=f'{peak/2**20:.0f} MiB' if peak else 'not measured';lines.append(f"| {labels[name]} | {statistics.median(cold):.0f} ms | {statistics.median(warm):.0f} MiB | {allocated} |")
lines+=['','## German specialization and uncertainty','','The German fine-tune and multilingual turbo control have identical architecture and the same 160-layer quantization mask (4-bit, group 64); neither has an architectural size advantage. The full-FP16 multilingual turbo is an additional control. Different file formats can affect load-time and sampled peak RSS.','','| Paired comparison | WER difference | Exploratory 95% paired-clip bootstrap interval |','| --- | ---: | ---: |']
for r in intervals:
    lo,hi=r['paired_clip_bootstrap_95_interval_pp'];lines.append(f"| {r['comparison']} | {r['delta_percentage_points']:+.2f} pp | [{lo:+.2f}, {hi:+.2f}] pp |")
lines+=['','Intervals use 10,000 resamples of the 20 clips (seed 0), not repeated latency runs as new observations. They describe this small read-speech sample; training overlap, spontaneous dictation, dialects and personal vocabulary were not controlled. There is no demonstrated reason here to switch solely because a model is German-focused.','','## Export validation','','The first Cohere checkpoint targeted another MLX layout. Reversing its published key map and splitting QKV preserved all 2,621 source tensors bit-for-bit; a deterministic sinusoidal position buffer was regenerated, and strict loading passed. That establishes storage reconstruction, not full upstream forward-pass parity. It produced 41.78% strict FLEURS WER with many omissions and is retained only as an exploratory implementation result. It is not used to judge the Cohere model family or Superwhisper. A native MLX-Audio BF16/Q4 export was therefore downloaded and measured separately.','','Voz compiled MIL inspection found uint6 LUT operations in the old encoder/decoder, int4 blockwise dequantization in the new encoder and int8 in the new decoder. Both expose FP16 I/O and contain mixed-precision data. Metadata saying float16 does not imply all weights are FP16. See `eval/asr/voz-quantization.json`. SDK and export changed together, so the timing/error changes cannot be assigned to quantization alone.','','## Model revisions','','| Label | Repository | Immutable revision |','| --- | --- | --- |']
for m in public_models:lines.append(f"| {m['name']} | {m['repository']} | `{m['revision']}` |")
lines+=['','Voz revisions: v0.1.0 = `8e7ab8ca342c6bb00f9347a25e53fe44543b2a40`; v0.5.0 = `81940d2b41329e1e157acbac8af95e23aa4e224b`. SDK 4.3.0 = `baf4e6e3b4655c8e54aa8d5a25215b5f35f899a7`. Exact local file hashes, commands, inputs, reference statuses and raw hypotheses are retained outside Git under `~/Library/Application Support/hushpen-comparison`.','','These are independent model/runtime tests. No Superwhisper or Handy app latency, VAD, vocabulary wrapper, cleanup or paste result has been measured. Availability and exclusions are documented in ASR-COMPARISON.md.']
a.report.write_text('\n'.join(lines)+'\n');print('Wrote aggregate-only JSON and results report.')
