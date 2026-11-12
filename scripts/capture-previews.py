"""Capture actual compiled SwiftUI layouts; all subprocesses have bounded execution."""
import json, pathlib, subprocess, time

def run(*args, timeout=60, check=True):
    return subprocess.run(args, check=check, timeout=timeout, text=True, capture_output=True)

output = pathlib.Path('build/previews'); output.mkdir(parents=True, exist_ok=True)
data = json.loads(run('xcrun','simctl','list','devices','available','-j').stdout)
devices = [d for ds in data['devices'].values() for d in ds]
for family in ('iPad', 'iPhone'):
    device = next(d for d in devices if family in d['name'])
    uid = device['udid']
    run('xcrun','simctl','boot',uid,check=False)
    run('xcrun','simctl','bootstatus',uid,'-b',timeout=110)
    run('xcrun','simctl','ui',uid,'appearance','light')
    run('xcrun','simctl','status_bar',uid,'override','--time','09:41','--batteryState','charged','--batteryLevel','100')
    run('xcrun','simctl','install',uid,'build/Build/Products/Debug-iphonesimulator/PianoBloom.app')
    for name, args in [('home', []), ('performance-portrait', ['--preview-performance'])] + ([('performance-landscape',['--preview-performance','--preview-landscape'])] if family == 'iPad' else []):
        run('xcrun','simctl','terminate',uid,'com.pianobloom.app',check=False)
        run('xcrun','simctl','launch',uid,'com.pianobloom.app',*args)
        time.sleep(4)
        run('xcrun','simctl','io',uid,'screenshot',str(output/f'{family}-{name}.png'))
        print(f'Captured {family}: {name}', flush=True)
    run('xcrun','simctl','shutdown',uid)
