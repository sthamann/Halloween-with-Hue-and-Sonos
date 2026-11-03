#!/usr/bin/env python3
"""Rebuild the curated CC0 bundle from verified OpenGameArt source files.
Downloads only audio/zip data; never executes or extracts archive scripts.
"""
from pathlib import Path
import array, hashlib, json, shutil, subprocess, sys, tempfile, urllib.request, wave, zipfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'Sources/HalloweenApp/Resources/Sounds'
LICENSE = 'https://creativecommons.org/publicdomain/zero/1.0/'
BASE = 'https://opengameart.org/sites/default/files/'
PACKS = {
 'ghosts': ('qubodup-GhostMoans.zip', '25962d146f4634a93efa7fbfe9cde63f4182189ced6105b4f92f23c65d8c2a43', 'qubodup', 'https://opengameart.org/content/ghost-monster-voice-moaning-growling'),
 'monsters': ('monster_sfx_pack.zip', 'f39c5ae356b1fc01284057ee48e35ec1a52fcc84bfa959b77d0a696adc8459e4', 'Ogrebane', 'https://opengameart.org/content/monster-sound-effects-pack'),
 'hits': ('horror_hit_soundpack_1.zip', '4bbdba64225d2ad2f5d23a04d71ccb18e6567c42f972a7f2dcb66d8acc5ed4f3', 'psychhead_', 'https://opengameart.org/content/horror-hit-soundpack-1'),
 'ambient': ('ambient_horror.wav', '23b0da9d4c92e58f76f88dc852579dabcc7acfe84a4ade7de6e01ce7e59b9c25', 'techiew', 'https://opengameart.org/content/ambient-horror'),
}
SELECTIONS = []
for n in range(1, 6):
 SELECTIONS.append(('ghosts', f'qubodup-GhostMoans/wav/qubodup-GhostMoan{n:02d}.wav', f'cc0-ghost-{n}', f'Geisterstimme {n}', 'Geister', 'wind'))
for n in range(1, 7):
 SELECTIONS.append(('monsters', f'monster_sfx_pack/monster-{n}.wav', f'cc0-monster-{n}', f'Monsterlaut {n}', 'Monster', 'pawprint.fill'))
for folder, n, ident, label in [('High', 1, 'high', 'Schriller Schreckmoment'), ('Mid', 1, 'mid', 'Dunkler Schreckmoment'), ('Bassy', 1, 'bass', 'Tiefer Horror-Schlag'), ('Very Bassy', 1, 'deep', 'Abgrund-Schlag'), ('High', 5, 'high-alt', 'Schriller Schreckmoment 2'), ('Mid', 5, 'mid-alt', 'Dunkler Schreckmoment 2')]:
 SELECTIONS.append(('hits', f'Horror Hit Soundpack 1/Sound/Pitches/{folder}/{folder} {n}.wav', f'cc0-hit-{ident}', label, 'Schreckeffekte', 'bolt.fill'))
SELECTIONS.append(('ambient', None, 'cc0-ambient-horror', 'Düstere Horror-Atmosphäre', 'Atmosphäre', 'moon.fog.fill'))

OWN = [('heartbeat', 'Herzschlag im Dunkeln', 'heart.fill'), ('storm', 'Gewitter', 'cloud.bolt.rain.fill'), ('knocks', 'Klopfen an der Tür', 'door.left.hand.open'), ('ghost', 'Geisterchor', 'wind'), ('laugh', 'Unheimliches Kichern', 'theatermasks.fill'), ('creak', 'Die knarrende Tür', 'door.right.hand.open')]

def sha(data): return hashlib.sha256(data).hexdigest()

def main():
 ffmpeg = shutil.which('ffmpeg')
 if not ffmpeg: raise SystemExit('ffmpeg is required to rebuild sounds.')
 OUT.mkdir(parents=True, exist_ok=True)
 catalog = []
 for ident, name, symbol in OWN:
  catalog.append(dict(id=ident, name=name, filename=ident+'.wav', symbol=symbol, category='Eigene Effekte', sha256=sha((OUT/(ident+'.wav')).read_bytes())))
 with tempfile.TemporaryDirectory(prefix='haunt-cc0-') as tmp:
  folder = Path(tmp); blobs = {}
  for key, (filename, digest, author, page) in PACKS.items():
   cache = Path('/tmp/haunt-cc0-sources')/filename
   blob = cache.read_bytes() if cache.exists() else urllib.request.urlopen(BASE+filename, timeout=60).read()
   if sha(blob) != digest: raise SystemExit('Source hash changed; recheck license and file: '+page)
   blobs[key] = blob; (folder/filename).write_bytes(blob)
  for pack, member, ident, name, category, symbol in SELECTIONS:
   archive, digest, author, page = PACKS[pack]
   if member:
    with zipfile.ZipFile(folder/archive) as z: raw = z.read(member)
   else: raw = blobs[pack]
   source = folder/(ident+'-source.wav'); source.write_bytes(raw)
   converted = folder/(ident+'-converted.wav')
   subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(source), '-ac', '1', '-ar', '44100', '-c:a', 'pcm_s16le', str(converted)], check=True)
   with wave.open(str(converted), 'rb') as w:
    params = w.getparams(); samples = array.array('h', w.readframes(w.getnframes()))
   if sys.byteorder != 'little': samples.byteswap()
   peak = max((abs(s) for s in samples), default=0)
   scale = min(1, 16383 / peak) if peak else 1
   if scale < 1: samples = array.array('h', (round(s * scale) for s in samples))
   # Keep very short effects available long enough for Sonos transport confirmation.
   if len(samples) < 2 * 44100: samples.extend([0] * (2 * 44100 - len(samples)))
   output_duration = len(samples) / 44100
   if sys.byteorder != 'little': samples.byteswap()
   filename = ident+'.wav'; dest = OUT/filename
   with wave.open(str(dest), 'wb') as w: w.setparams(params); w.writeframes(samples.tobytes())
   catalog.append(dict(id=ident, name=name, filename=filename, symbol=symbol, category=category,
     credit=dict(author=author, sourceURL=page, license='CC0 1.0', licenseURL=LICENSE),
     provenance=dict(downloadURL=BASE+archive, archiveSHA256=digest, originalMember=member or archive,
       originalSHA256=sha(raw), verifiedOn='2026-10-12', transformation='Mono PCM16 WAV / 44100 Hz; peak attenuation only to <= -6 dBFS; trailing silence to minimum 2 seconds for short clips'),
     sha256=sha(dest.read_bytes()), duration=output_duration))
   print(f'{name}: {output_duration:.2f}s')
 (OUT/'sound-catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
 notices = OUT/'Licenses'; notices.mkdir(exist_ok=True)
 (notices/'CC0-1.0.txt').write_text('CC0 1.0 Universal\n\nThe third-party recordings in this bundle are offered under CC0 1.0 by their respective authors.\nCanonical license: '+LICENSE+'\nLegal code: https://creativecommons.org/publicdomain/zero/1.0/legalcode\n\nSources and authors are listed in SOUND_CREDITS.md and sound-catalog.json.\nThe original six generated Haunt effects are identified separately; they are not third-party CC0 recordings.\n')
 lines = ['# Sound credits', '', '18 third-party recordings are bundled under CC0 1.0 Universal. The six original generated Haunt effects are separate.', '', 'License: '+LICENSE, '', 'The source pages were checked on 2026-10-12. Audio was converted to mono 16-bit PCM WAV at 44100 Hz and attenuated only where necessary to keep sample peaks at or below -6 dBFS. Very short effects have trailing silence up to a minimum total length of two seconds so Sonos can confirm playback. Full source filenames, checksums and conversion notes are in sound-catalog.json.', '', '| Sound | Author | Source | License |', '|---|---|---|---|']
 for item in catalog:
  if 'credit' in item:
   c=item['credit']; lines.append(f"| {item['name']} | {c['author']} | [{item['provenance']['originalMember']}]({c['sourceURL']}) | [{c['license']}]({c['licenseURL']}) |")
 text='\n'.join(lines)+'\n'
 (notices/'SOUND_CREDITS.md').write_text(text)
 (ROOT/'SOUND_CREDITS.md').write_text(text)
 print(f'Bundled: {len(catalog)} clips, {len(SELECTIONS)} CC0.')

if __name__ == '__main__': main()
