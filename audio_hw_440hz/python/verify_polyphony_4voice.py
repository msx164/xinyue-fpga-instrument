from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt


# ============================================================
# Paths
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

PCM_FILE = PROJECT_ROOT / "polyphony_4voice_pcm.txt"


# ============================================================
# Audio parameters
# ============================================================

SAMPLE_RATE = 48000


# ============================================================
# Check input file
# ============================================================

print(f"Project root : {PROJECT_ROOT}")
print(f"PCM file     : {PCM_FILE}")
print()


if not PCM_FILE.exists():

    raise FileNotFoundError(
        "\nCannot find:\n"
        f"{PCM_FILE}\n\n"
        "Run tb_polyphony_4voice in ModelSim first."
    )


# ============================================================
# Load PCM
# ============================================================

pcm = np.loadtxt(
    PCM_FILE,
    dtype=np.float64
)


print(f"Samples: {len(pcm)}")


# ============================================================
# Remove DC
# ============================================================

pcm = pcm - np.mean(pcm)


# ============================================================
# Window
# ============================================================

window = np.hanning(len(pcm))

windowed = pcm * window


# ============================================================
# FFT
# ============================================================

spectrum = np.fft.rfft(windowed)

magnitude = np.abs(spectrum)

frequency = np.fft.rfftfreq(
    len(pcm),
    d=1.0 / SAMPLE_RATE
)


# ============================================================
# Target frequencies
# ============================================================

targets = [
    440.000,
    523.251,
    659.255,
    783.991,
]


# ============================================================
# Check each target locally
# ============================================================

def check_target(target, tolerance=10.0):

    mask = (
        (frequency >= target - tolerance) &
        (frequency <= target + tolerance)
    )

    if not np.any(mask):
        return False, None, 0.0

    local_freq = frequency[mask]
    local_mag = magnitude[mask]

    index = np.argmax(local_mag)

    return (
        True,
        local_freq[index],
        local_mag[index]
    )


print()
print("Target frequency check:")
print()


all_pass = True


for target in targets:

    found, detected, mag = check_target(target)

    if not found:

        all_pass = False

        print(
            f"{target:8.3f} Hz -> FAIL"
        )

    else:

        error = abs(
            detected - target
        )

        passed = error <= 10.0

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
        "POLYPHONY 4 VOICE FFT TEST PASS"
    )

else:

    print(
        "POLYPHONY 4 VOICE FFT TEST FAIL"
    )


# ============================================================
# Plot
# ============================================================

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
    "4-Voice Polyphony Spectrum"
)

plt.grid()

plt.show()