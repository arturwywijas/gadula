# autor: Codex, gadula-dyktowanie-20260927
"""Sprawdza wynik syntetycznego benchmarku, bez oceniania prywatnych nagrań."""
import json
import sys
from collections import Counter

records = [json.loads(line) for line in open(sys.argv[1]) if line.startswith('{')]
required = sys.argv[2:] or ['krotkie.caf', 'cisza.wav', 'dlugie.caf', 'nazwy.caf']
errors = []
seen = Counter()
for row in records:
    name, text = row['file'], row['text']
    seen[(name, row['mode'], row['attempt'])] += 1
    lower = text.lower()
    if name == 'krotkie.caf':
        ok = lower.strip(' .!?') == 'tak'
    elif name == 'cisza.wav':
        ok = not text.strip()
    elif name == 'nazwy.caf':
        ok = all(word in text for word in ['Gaduła', 'Artur Wywijas', 'Frankentools', 'Unity', 'Super Hierarchy'])
    elif name in ['dlugie.caf', 'gesta.caf']:
        phrases = ['planu pracy', 'zapisanych wcześniej pomysłów', 'kolejności działań',
                   'mikrofonu i szybkości aplikacji', 'wyników wykonanych testów',
                   'zapisanie ustaleń i przygotowanie nowej wersji programu',
                   'nie wysyłaj tej wiadomości przed sprawdzeniem jej treści']
        ok = all(phrase in lower for phrase in phrases) and lower.rstrip().endswith('jej treści.')
    elif name in ['cicha-koncowka.wav', 'dluga-pauza.wav']:
        ok = 'planu pracy na następny tydzień' in lower and lower.rstrip().endswith('nie.')
    else:
        continue
    if not ok:
        errors.append(f"FAIL {name} {row['mode']} próba {row['attempt']}: {text}")
for name in required:
    for mode in ['batch', 'stream']:
        for attempt in [1, 2]:
            if seen[(name, mode, attempt)] != 1:
                errors.append(f'FAIL brak jednoznacznego wyniku: {name} {mode} {attempt}')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(f'PASS {len(required) * 4} wyników rzeczywistego STT dla: {", ".join(required)}')
