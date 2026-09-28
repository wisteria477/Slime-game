from pathlib import Path
import struct
root=Path(__file__).resolve().parents[1]
required=[
 'project.godot','scenes/Main.tscn','scripts/main.gd','scripts/camera_rig.gd',
 'scripts/build_system.gd','scripts/slime_agent.gd','scripts/household.gd',
 'assets/models/nim_slime_current.glb','export_presets.cfg'
]
for rel in required:
 p=root/rel
 if not p.exists() or p.stat().st_size==0:
  raise SystemExit(f'MISSING: {rel}')
p=root/'assets/models/nim_slime_current.glb'
data=p.read_bytes()[:12]
if len(data)!=12 or data[:4]!=b'glTF' or struct.unpack('<I',data[4:8])[0]!=2:
 raise SystemExit('Invalid GLB header')
texts={rel:(root/rel).read_text(errors='replace') for rel in required if rel.endswith(('.gd','.godot','.tscn','.cfg'))}
joined='\n'.join(texts.values())
checks={
 'baby logic':'add_baby(',
 'autonomy':'_choose_next_goal',
 'build mode':'_toggle_build',
 'save':'SAVE_PATH',
 'needs':'hunger',
 'no death':'BABY_GROW_SECONDS',
 'current model':'nim_slime_current.glb',
 'mobile touch':'InputEventScreenTouch',
}
for name,needle in checks.items():
 if needle not in joined:
  raise SystemExit(f'MISSING FEATURE MARKER: {name}')
for rel,text_value in texts.items():
 if not rel.endswith('.gd'):
  continue
 for a,b in [('(',')'),('[',']'),('{','}')]:
  if text_value.count(a)!=text_value.count(b):
   raise SystemExit(f'Unbalanced {a}{b} in {rel}')
print('Slime Life bare-minimum package validation PASSED')
