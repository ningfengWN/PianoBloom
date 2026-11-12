import pathlib,struct,json,collections
root=pathlib.Path(__file__).resolve().parent.parent
import argparse, urllib.request, zipfile, io
parser = argparse.ArgumentParser(description="Rebuild CC BY-SA 4.0 Hanon data from the Mutopia source MIDI archive")
parser.add_argument("--midi-dir", type=pathlib.Path, help="Use a previously downloaded directory of hanonNN.mid files")
args = parser.parse_args()
if args.midi_dir:
 midi_dir = args.midi_dir
else:
 import tempfile
 temporary = tempfile.TemporaryDirectory()
 midi_dir = pathlib.Path(temporary.name)
 url = "https://www.mutopiaproject.org/ftp/HanonCL/virtuoso-pianist-pt1/virtuoso-pianist-pt1-mids.zip"
 archive = urllib.request.urlopen(url, timeout=30).read()
 with zipfile.ZipFile(io.BytesIO(archive)) as z:
  for name in z.namelist():
   if pathlib.Path(name).name.startswith("hanon") and name.endswith(".mid"):
    (midi_dir/pathlib.Path(name).name).write_bytes(z.read(name))
def events(path):
 data=pathlib.Path(path).read_bytes(); tpq=int.from_bytes(data[12:14],'big');pos=8+int.from_bytes(data[4:8],'big');ons={}
 while pos<len(data):
  size=int.from_bytes(data[pos+4:pos+8],'big');b=data[pos+8:pos+8+size];pos+=8+size;i=0;t=0;running=0;active={}
  def vlq():
   nonlocal i
   v=0
   while True:
    c=b[i];i+=1;v=(v<<7)|(c&127)
    if c<128:return v
  while i<len(b):
   t+=vlq();s=b[i]
   if s>=128:i+=1
   else:s=running
   if s==255:i+=1;n=vlq();i+=n
   elif s in (240,247):n=vlq();i+=n
   else:
    running=s;n=1 if s&240 in (192,208) else 2;args=b[i:i+n];i+=n
    if s&240==144 and args[1]>0:ons.setdefault(t,[]).append(args[0])
 return tpq,sorted(ons.items())
strings=[]
for n in range(1,21):
 tpq,ons=events(midi_dir/f'hanon{n:02}.mid')
 assert all(len(v)==2 for _,v in ons[:-1])
 rows=[]
 for idx,(tick,notes) in enumerate(ons):
  notes=sorted(notes);split=len(notes)//2
  dur=(ons[idx+1][0]-tick)/tpq if idx+1<len(ons) else 2
  assert dur in (.25,2)
  rows.append(f'{".".join(map(str,notes[split:]))}/{".".join(map(str,notes[:split]))}/{dur:g}')
 strings.append('        "'+' '.join(rows)+'"')
code='''import Foundation

// Adapted score data © Steve Taylor and Javier Ruiz-Alma, CC BY-SA 4.0.
// Mutopia-2015/07/23-2037. See HANON_SOURCES.md.
// Format: right pitches / left pitches / quarter-note duration. Repeats expanded below.
enum HanonScores {
    static let all: [PianoScore] = packed.enumerated().map { index, text in
        let cells = text.split(separator: " ").map { $0.split(separator: "/") }
        let body = Array(cells.dropLast())
        let repeated = body + body + [cells.last!]
        var beat = 0.0
        let events: [ScoreEvent] = repeated.map { cell in
            let duration = Double(cell[2])!
            defer { beat += duration }
            return ScoreEvent(beat: beat, duration: duration,
                right: cell[0].split(separator: ".").map { Int($0)! },
                left: cell[1].split(separator: ".").map { Int($0)! })
        }
        return PianoScore(id: "hanon-\\(index + 1)", title: "哈农第 \\(index + 1) 首",
            detail: "原谱双手 · 2/4 拍 · 含反复", beatsPerBar: 2, events: events)
    }
    private static let packed: [String] = [
'''+',\n'.join(strings)+'\n    ]\n}\n'
(root/'PianoBloom/HanonScores.swift').write_text(code)
print('Generated',len(strings),'full two-hand scores from source MIDI')
