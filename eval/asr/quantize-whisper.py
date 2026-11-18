"""Create a matched local Q4 control from an already downloaded MLX Whisper."""
import argparse,json
from pathlib import Path
import mlx.core as mx
import mlx.nn as nn
from mlx.utils import tree_flatten
from mlx_whisper.load_models import load_model
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);p.add_argument('--match-model',type=Path);a=p.parse_args()
a.destination.mkdir(parents=True,exist_ok=False)
model=load_model(str(a.source),mx.float16)
if a.match_model:
    reference_path=a.match_model/'weights.npz'
    if not reference_path.exists():reference_path=a.match_model/'weights.safetensors'
    target=mx.load(str(reference_path))
    expected_scales={k for k in target if k.endswith('.scales')}
    assert expected_scales, 'Reference has no quantized layers'
    reference_config=json.loads((a.match_model/'config.json').read_text())
    original_config=json.loads((a.source/'config.json').read_text())
    assert all(original_config[k]==v for k,v in reference_config.items() if k.startswith('n_')), 'Architecture differs'
    nn.quantize(model,group_size=64,bits=4,class_predicate=lambda path,module:path+'.scales' in target)
else:
    nn.quantize(model,group_size=64,bits=4)
mx.eval(model.parameters())
if a.match_model:
    actual_scales={k for k,v in tree_flatten(model.parameters()) if k.endswith('.scales')}
    assert actual_scales==expected_scales, 'Quantization mask differs'
mx.save_safetensors(str(a.destination/'weights.safetensors'),dict(tree_flatten(model.parameters())))
config=json.loads((a.source/'config.json').read_text());config['quantization']={'bits':4,'group_size':64}
(a.destination/'config.json').write_text(json.dumps(config,indent=2)+'\n')
print('Created matched Whisper Q4 control.')
