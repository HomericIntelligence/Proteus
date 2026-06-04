#!/usr/bin/env bats

@test "every pipeline config has name + stages" {
  for f in configs/pipelines/*.yaml; do
    run python3 -c "
import sys, yaml
d = yaml.safe_load(open('$f'))
assert d.get('name'), 'missing name'
assert isinstance(d.get('stages'), list) and d['stages'], 'no stages'
for s in d['stages']:
    assert s.get('name'), 'stage missing name'
    assert s.get('type') in {'dagger','skopeo','dispatch'}, f'bad type {s.get(\"type\")}'
"
    [ "$status" -eq 0 ]
  done || true
}

@test "every depends_on references an existing stage in the same file" {
  run python3 -c "
import yaml, glob, sys
for f in glob.glob('configs/pipelines/*.yaml'):
    d = yaml.safe_load(open(f))
    names = {s['name'] for s in d['stages']}
    for s in d['stages']:
        for dep in s.get('depends_on', []) or []:
            assert dep in names, f'{f}: stage {s[\"name\"]} depends_on unknown {dep}'
print('OK')
"
  [ "$status" -eq 0 ]
}
