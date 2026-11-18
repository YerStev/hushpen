"""Persistent local ASR worker; stdout is a private pipe, never a log."""
import contextlib,json,sys,time
import numpy as np
import mlx.core as mx
family,path=sys.argv[1:]
runtime_start=time.perf_counter()
# Suppress library console output: some engines print recognized words.
with open('/dev/null','w') as sink, contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
    if family=='whisper':
        import mlx_whisper
        from mlx_whisper.transcribe import ModelHolder
        start=time.perf_counter()
        ModelHolder.get_model(path,mx.float16)
    else:
        from mlx_audio.stt.utils import load_model
        start=time.perf_counter()
        model=load_model(path,model_type=family,strict=True)
    mx.synchronize()
print(json.dumps({'ready':True,'load_ms':(time.perf_counter()-start)*1000,'runtime_import_ms':(start-runtime_start)*1000}),flush=True)
for line in sys.stdin:
    try:
        audio=np.fromfile(json.loads(line)['pcm'],dtype='<f4')
        with open('/dev/null','w') as sink,contextlib.redirect_stdout(sink),contextlib.redirect_stderr(sink):
            start=time.perf_counter()
            if family=='whisper':
                result=mlx_whisper.transcribe(audio,path_or_hf_repo=path,language='de',temperature=0,condition_on_previous_text=False,verbose=None)
                text=result['text']
            else:
                options={'verbose':False}
                if family in ['cohere_asr','canary','qwen3_asr','voxtral_realtime']: options['language']='de'
                result=model.generate(mx.array(audio),**options)
                text=result.text
            mx.synchronize()
            elapsed=(time.perf_counter()-start)*1000
        print(json.dumps({'text':text,'stt_ms':elapsed,'mlx_peak_bytes':mx.get_peak_memory()}),flush=True)
    except Exception as e:
        print(json.dumps({'error':type(e).__name__}),flush=True)
