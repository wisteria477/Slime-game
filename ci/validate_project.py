from pathlib import Path
root=Path(__file__).resolve().parents[1]
required=[
 'project.godot','scenes/Main.tscn','scripts/main.gd','scripts/camera_rig.gd',
 'scripts/build_system.gd','scripts/slime_agent.gd','scripts/household.gd',
 'assets/icons/slime_life_icon.svg','export_presets.cfg'
]
for rel in required:
 p=root/rel
 if not p.exists() or p.stat().st_size==0:
  raise SystemExit(f'MISSING: {rel}')
texts={rel:(root/rel).read_text(errors='replace') for rel in required if rel.endswith(('.gd','.godot','.tscn','.cfg','.svg'))}
joined='\n'.join(texts.values())
checks={
 'baby logic':'add_baby(',
 'autonomy':'_choose_next_goal',
 'build mode':'_toggle_build',
 'save':'SAVE_PATH',
 'needs':'hunger',
 'no death':'BABY_GROW_SECONDS',
 'mobile touch':'InputEventScreenTouch',
 'fallback character':'_make_fallback_slime',
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
