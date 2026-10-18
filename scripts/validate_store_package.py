#!/usr/bin/env python3
"""Validate local listing assets and report actual submission blockers (no network mutations)."""
import json, plistlib, struct, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
package=root/'AppStore'
config=json.loads((package/'submission.json').read_text())
artifact=json.loads((package/'build-artifact.json').read_text())
errors=[]; blockers=[]; checks=[]
limits={'name':30,'subtitle':30,'keywords':100,'promotional_text':170,'description':4000}
for locale in ['he','en-US']:
 for field,limit in limits.items():
  text=(package/'metadata'/locale/(field+'.txt')).read_text().strip()
  if not text or len(text)>limit:errors.append(f'{locale}/{field}: {len(text)}/{limit}')
  else:checks.append(f'{locale}/{field}: {len(text)}/{limit}')
for family,expected in [('iphone-large',(1320,2868)),('ipad-13',(2064,2752))]:
 files=sorted((package/'screenshots/he'/family).glob('*.jpg'))
 if not files or len(files)>10:errors.append(f'{family}: expected 1–10 screenshots')
 for file in files:
  result=subprocess.check_output(['sips','-g','pixelWidth','-g','pixelHeight','-g','hasAlpha',str(file)],text=True)
  values=dict(line.strip().split(': ',1) for line in result.splitlines() if ': ' in line)
  dimensions=(int(values['pixelWidth']),int(values['pixelHeight']))
  if dimensions!=expected or values['hasAlpha']!='no':errors.append(f'Invalid screenshot: {file.name}, {dimensions}, alpha={values["hasAlpha"]}')
 checks.append(f'{family}: {len(files)} opaque JPEG screenshots at {expected[0]} × {expected[1]}')
icon=package/'AppIcon-1024.png'
header=icon.read_bytes()[:26]
if header[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',header[16:24])!=(1024,1024) or header[25] in [4,6]:errors.append('App icon must be opaque 1024 × 1024 PNG')
else:checks.append('App icon: opaque 1024 × 1024 PNG')
archive=root/artifact.get('archive','build/AppStore/Mila.xcarchive')
if (archive/'Info.plist').exists():
 info=plistlib.loads((archive/'Info.plist').read_bytes())
 app=archive/'Products/Applications/HebrewVoice.app'
 appinfo=plistlib.loads((app/'Info.plist').read_bytes())
 if appinfo.get('CFBundleIdentifier')!=config['bundle_id']:errors.append('Archive bundle identifier mismatch')
 if appinfo.get('CFBundleShortVersionString')!=config['version']:errors.append('Archive version mismatch')
 if appinfo.get('CFBundleVersion')!=config['build_number']:errors.append('Archive build number mismatch')
 activityinfo=plistlib.loads((app/'PlugIns/MilaActivity.appex/Info.plist').read_bytes())
 if activityinfo.get('CFBundleVersion')!=config['build_number']:errors.append('Activity build number mismatch')
 verify=subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True)
 if verify.returncode:errors.append('Archive code-signature verification failed: '+verify.stderr.strip())
 else:checks.append('Release archive exists and embedded signatures verify')
 checks.append('Archive signing identity: '+info.get('ApplicationProperties',{}).get('SigningIdentity','unknown'))
else:errors.append('Release archive missing')
for field in ['app_store_app_id','price','territories','copyright','support_url','privacy_policy_url']:
 if config.get(field) is None:blockers.append('Missing '+field)
contact = dict(config.get('review_contact', {}))
private_contact = root / config.get('review_contact_file', 'AppStore/review-contact.local.json')
if private_contact.exists():
 supplied = json.loads(private_contact.read_text())
 for key, source in [('first_name','contactFirstName'),('last_name','contactLastName'),('email','contactEmail'),('phone','contactPhone')]:
  contact[key] = supplied.get(source) or contact.get(key)
for field,value in contact.items():
 if not value:blockers.append('Missing review_contact.'+field)
ipa=root/artifact['ipa']
if not ipa.exists():blockers.append('App Store IPA export missing')
else:checks.append('App Store IPA exported: '+str(ipa.relative_to(root)))
if not config.get('app_store_app_id'):blockers.append('App Store record creation requires the signed-in App Store Connect browser session')
report={'state':('LOCAL_PACKAGE_ERRORS' if errors else 'LOCAL_PACKAGE_VALID_SUBMISSION_BLOCKED' if blockers else config.get('status','LOCAL_PACKAGE_VALID')),'checks':checks,'errors':errors,'submission_blockers':blockers,'submitted':config.get('status') in ['WAITING_FOR_REVIEW','IN_REVIEW','READY_FOR_DISTRIBUTION'],'apple_server_validation_completed':(package/'apple-validation.json').exists() and json.loads((package/'apple-validation.json').read_text()).get('passed',False)}
(package/'validation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
sys.exit(1 if errors else 2 if blockers else 0)
