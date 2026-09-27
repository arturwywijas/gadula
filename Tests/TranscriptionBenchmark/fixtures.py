# autor: Codex, gadula-dyktowanie-20260927
"""Lokalne próbki syntetyczne macOS Zosia, 165 słów/min, mono 16 kHz."""
import array
import pathlib
import subprocess
import wave

folder = pathlib.Path('.build/transcription-fixtures')
folder.mkdir(parents=True, exist_ok=True)
sentences = [
    'Pierwszy punkt dotyczy przygotowania planu pracy na następny tydzień.',
    'Drugi punkt to sprawdzenie wszystkich zapisanych wcześniej pomysłów.',
    'Trzeci punkt dotyczy spotkania zespołu i ustalenia kolejności działań.',
    'Czwarty punkt to rozmowa o działaniu mikrofonu i szybkości aplikacji.',
    'Piąty punkt dotyczy dokumentacji oraz wyników wykonanych testów.',
    'Szósty punkt to zapisanie ustaleń i przygotowanie nowej wersji programu.',
    'Nie wysyłaj tej wiadomości przed sprawdzeniem jej treści.',
]
def say(name, text):
    target = folder / name
    subprocess.run(['say', '-v', 'Zosia', '-r', '165', '--data-format=LEF32@16000', '-o', str(target), text], check=True)
    return target

say('krotkie.caf', 'Tak.')
say('dlugie.caf', ' [[slnc 1000]] '.join(sentences) + ' [[slnc 1000]]')
subprocess.run(['say', '-v', 'Zosia', '-r', '220', '--data-format=LEF32@16000', '-o', str(folder / 'gesta.caf'), ' '.join(sentences).replace('.', ',')], check=True)
say('nazwy.caf', 'Gaduła pomaga zapisywać pomysły. Artur Wywijas tworzy Frankentools. Rozmawiamy o programie Unity i projekcie Super Hierarchy.')
def write_wave(name, samples):
    with wave.open(str(folder / name), 'wb') as result:
        result.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
        result.writeframes(samples.tobytes())

write_wave('cisza.wav', array.array('h', [0]) * 80000)
parts = []
for name, text in [('poczatek', sentences[0]), ('ciche-nie', 'Nie.')]:
    caf = say(name + '.caf', text)
    wav = folder / (name + '.wav')
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', str(caf), str(wav)], check=True)
    with wave.open(str(wav), 'rb') as f:
        parts.append(array.array('h', f.readframes(f.getnframes())))
quiet = array.array('h', (round(sample * 0.004) for sample in parts[1]))
write_wave('cicha-koncowka.wav', parts[0] + array.array('h', [0]) * 16000 + quiet)
write_wave('dluga-pauza.wav', parts[0] + array.array('h', [2]) * 160000 + parts[1])
print(folder)
