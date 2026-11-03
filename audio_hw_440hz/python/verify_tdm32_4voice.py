from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

PCM_FILE = PROJECT_ROOT / "tdm32_4voice_pcm.txt"

SAMPLE_RATE = 48000


print(f"PCM file: {PCM_FILE}")
print()


if not PCM_FILE.exists():
    raise FileNotFoundError(
        f"Cannot find PCM file:\n{PCM_FILE}"
    )


pcm = np.loadtxt(
    PCM_FILE,
    dtype=np.float64
)


print(f"Samples: {len(pcm)}")


pcm = pcm - np.mean(pcm)


window = np.hanning(
    len(pcm)
)


spectrum = np.fft.rfft(
    pcm * window
)


magnitude = np.abs(
    spectrum
)


frequency = np.fft.rfftfreq(
    len(pcm),
    d=1.0 / SAMPLE_RATE
)


targets = [
    440.000,
    523.251,
    659.255,
    783.991,
]


print()
print("Target frequency check:")
print()


all_pass = True


for target in targets:

    mask = (
        (frequency >= target - 10.0) &
        (frequency <= target + 10.0)
    )


    local_frequency = frequency[mask]
    local_magnitude = magnitude[mask]


    index = np.argmax(
        local_magnitude
    )


    detected = local_frequency[index]

    error = abs(
        detected - target
    )


    passed = (
        error <= 10.0
    )


    all_pass &= passed


    print(
        f"{target:8.3f} Hz "
        f"-> {detected:8.3f} Hz "
        f"error={error:6.3f} Hz "
        f"{'PASS' if passed else 'FAIL'}"
    )


print()


if all_pass:

    print(
        "TDM32 4-VOICE FFT TEST PASS"
    )

else:

    print(
        "TDM32 4-VOICE FFT TEST FAIL"
    )


plt.figure()

plt.plot(
    frequency,
    magnitude
)

plt.xlim(
    300,
    1000
)

plt.xlabel(
    "Frequency (Hz)"
)

plt.ylabel(
    "Magnitude"
)

plt.title(
    "TDM32 Engine - 4 Active Voices"
)

plt.grid()

plt.show()