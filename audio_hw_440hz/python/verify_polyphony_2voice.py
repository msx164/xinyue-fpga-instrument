from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt


# ============================================================
# Paths
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

PCM_FILE = PROJECT_ROOT / "polyphony_2voice_pcm.txt"


# ============================================================
# Audio parameters
# ============================================================

SAMPLE_RATE = 48000


# ============================================================
# Check PCM file
# ============================================================

print(f"Python script : {SCRIPT_DIR}")
print(f"Project root  : {PROJECT_ROOT}")
print(f"PCM file      : {PCM_FILE}")
print()


if not PCM_FILE.exists():

    raise FileNotFoundError(
        "\n"
        "Cannot find RTL-generated PCM file:\n"
        f"{PCM_FILE}\n\n"
        "Please run tb_polyphony_2voice in ModelSim first "
        "and make sure polyphony_2voice_pcm.txt is generated "
        "in the project root directory."
    )


# ============================================================
# Load RTL-generated PCM
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
# Apply Hann window
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
# Find strong frequency peaks
# ============================================================

sorted_indices = np.argsort(magnitude)[::-1]

peaks = []


for index in sorted_indices:

    freq = frequency[index]

    if freq < 20:
        continue

    if all(
        abs(freq - existing) > 20
        for existing in peaks
    ):

        peaks.append(freq)

    if len(peaks) >= 5:
        break


print()
print("Strongest frequency peaks:")


for freq in peaks:

    print(f"{freq:.3f} Hz")


# ============================================================
# Check target frequencies
# ============================================================

def has_peak(target, tolerance=10.0):

    return any(
        abs(peak - target) <= tolerance
        for peak in peaks
    )


pass_440 = has_peak(440.0)
pass_880 = has_peak(880.0)


print()
print(f"440 Hz detected : {pass_440}")
print(f"880 Hz detected : {pass_880}")


if pass_440 and pass_880:

    print()
    print("POLYPHONY 2 VOICE FFT TEST PASS")

else:

    print()
    print("POLYPHONY 2 VOICE FFT TEST FAIL")


# ============================================================
# Plot spectrum
# ============================================================

plt.figure()

plt.plot(
    frequency,
    magnitude
)

plt.xlim(0, 1500)

plt.xlabel("Frequency (Hz)")
plt.ylabel("Magnitude")

plt.title(
    "2-Voice Polyphony Spectrum"
)

plt.grid()

plt.show()