#!/usr/bin/env python3
"""Seed only explicit demo transcripts into a simulator; no shipping-app demo backdoor."""
import argparse, json, subprocess
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('simulator')
parser.add_argument('--remove', action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
bundle='com.hebrewvoice.mila'
subprocess.run(['xcrun','simctl','terminate',args.simulator,bundle],capture_output=True)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.simulator,bundle,'data'],text=True).strip())
folder=container/'Library/Application Support/Transcripts'
folder.mkdir(parents=True,exist_ok=True)
fixtures=json.loads((root/'AppStore/screenshot-fixtures.json').read_text())
for item in fixtures:
 file=folder/(item['id']+'.json')
 if file.exists():
  existing=json.loads(file.read_text())
  if existing != item:raise SystemExit('Refusing to overwrite a changed transcript: '+str(file))
 if args.remove:file.unlink(missing_ok=True)
 else:file.write_text(json.dumps(item,ensure_ascii=False))
subprocess.run(['xcrun','simctl','status_bar',args.simulator,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100'],check=True)
subprocess.run(['xcrun','simctl','launch',args.simulator,bundle],check=True)
print('Removed demo fixtures.' if args.remove else 'Seeded two explicitly labelled demo transcripts.')
