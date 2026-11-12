"""Capture actual compiled SwiftUI layouts; all subprocesses have bounded execution."""
import json, pathlib, subprocess, time, struct, hashlib, argparse, os, signal

def run(*args, timeout=60, check=True):
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate(timeout=5)
        raise TimeoutError(f"Command exceeded {timeout}s: {args}")
    if check and process.returncode:
        raise RuntimeError(f"Command failed: {args}: {stderr[-2500:]}")
    return subprocess.CompletedProcess(args, process.returncode, stdout, stderr)

parser = argparse.ArgumentParser()
parser.add_argument('--family', choices=['iPad', 'iPhone', 'all'], default='all')
parser.add_argument('--skip-landscape', action='store_true')
options = parser.parse_args()
output = pathlib.Path('build/previews'); output.mkdir(parents=True, exist_ok=True)
data = json.loads(run('xcrun','simctl','list','devices','available','-j').stdout)
devices = [d for ds in data['devices'].values() for d in ds]
failures = []
for family in (('iPad', 'iPhone') if options.family == 'all' else [options.family]):
    device = next(d for d in devices if family in d['name'])
    uid = device['udid']
    run('xcrun','simctl','boot',uid,check=False)
    run('xcrun','simctl','bootstatus',uid,'-b',timeout=110)
    run('xcrun','simctl','ui',uid,'appearance','light')
    run('xcrun','simctl','status_bar',uid,'override','--time','09:41','--batteryState','charged','--batteryLevel','100')
    run('xcrun','simctl','install',uid,'build/Build/Products/Debug-iphonesimulator/PianoBloom.app')
    for name, args in [('home', []), ('performance-portrait', ['--preview-performance']), ('guided', ['--preview-performance','--preview-guided'])] + ([('performance-landscape',['--preview-performance','--preview-landscape'])] if family == 'iPad' and not options.skip_landscape else []):
        run('xcrun','simctl','terminate',uid,'com.pianobloom.app',check=False)
        run('xcrun','simctl','launch',uid,'com.pianobloom.app',*args)
        time.sleep(4)
        run('xcrun','simctl','io',uid,'screenshot',str(output/f'{family}-{name}.png'))
        image_path = output/f'{family}-{name}.png'
        if name != 'home':
            assert hashlib.sha256(image_path.read_bytes()).digest() != hashlib.sha256((output/f'{family}-home.png').read_bytes()).digest(), 'Performance preview did not open'
        if name == 'performance-landscape':
            width, height = struct.unpack('>II', image_path.read_bytes()[16:24])
            if width <= height:
                container = pathlib.Path(run('xcrun','simctl','get_app_container',uid,'com.pianobloom.app','data').stdout.strip())
                diagnostic = container/'Documents/orientation-error.txt'
                detail = diagnostic.read_text() if diagnostic.exists() else 'No UIKit error returned'
                (output/'orientation-diagnostic.txt').write_text(detail)
                failures.append(f'Landscape request failed: {width}x{height}; {detail}')
        print(f'Captured {family}: {name}', flush=True)
    run('xcrun','simctl','shutdown',uid)

assert not failures, "\n".join(failures)
