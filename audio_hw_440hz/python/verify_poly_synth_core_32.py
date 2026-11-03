from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt


# ============================================================
# Paths
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent


# ============================================================
# Audio parameters
# ============================================================

SAMPLE_RATE = 48000


# ============================================================
# MIDI Note -> Frequency
#
# MIDI 69 = A4 = 440 Hz
# ============================================================

def midi_frequency(note: int) -> float:
    return 440.0 * (
        2.0 ** (
            (note - 69) / 12.0
        )
    )


# ============================================================
# Analyze one PCM test case
# ============================================================

def analyze_case(
    filename: str,
    voice_count: int
):

    pcm_file = (
        PROJECT_ROOT /
        filename
    )

    print()
    print("=" * 72)
    print(f"{voice_count} VOICE FFT TEST")
    print("=" * 72)

    print(f"PCM file : {pcm_file}")

    if not pcm_file.exists():
        raise FileNotFoundError(
            "\nCannot find PCM file:\n"
            f"{pcm_file}\n\n"
            "Please run tb_poly_synth_core_32 in ModelSim first."
        )

    # ========================================================
    # Load PCM
    # ========================================================

    pcm = np.loadtxt(
        pcm_file,
        dtype=np.float64
    )

    print(f"Samples  : {len(pcm)}")

    if len(pcm) == 0:
        raise RuntimeError(
            f"PCM file is empty: {pcm_file}"
        )

    # ========================================================
    # Remove DC component
    # ========================================================

    pcm = (
        pcm -
        np.mean(pcm)
    )

    # ========================================================
    # Hann window
    # ========================================================

    window = np.hanning(
        len(pcm)
    )

    windowed_pcm = (
        pcm *
        window
    )

    # ========================================================
    # FFT
    # ========================================================

    spectrum = np.fft.rfft(
        windowed_pcm
    )

    magnitude = np.abs(
        spectrum
    )

    frequency = np.fft.rfftfreq(
        len(pcm),
        d=1.0 / SAMPLE_RATE
    )

    if len(magnitude) == 0:
        raise RuntimeError(
            "FFT result is empty."
        )

    global_max = np.max(
        magnitude
    )

    if global_max <= 0.0:
        raise RuntimeError(
            "PCM contains no useful signal."
        )

    # ========================================================
    # Frequency resolution
    # ========================================================

    fft_resolution = (
        SAMPLE_RATE /
        len(pcm)
    )

    print(
        f"FFT bin  : {fft_resolution:.3f} Hz"
    )

    print()
    print(
        "Note   Target(Hz)   Detected(Hz)   "
        "Error(Hz)   Relative   Result"
    )

    print("-" * 72)

    all_pass = True

    detected_results = []

    # ========================================================
    # Voice0 corresponds to MIDI Note 48.
    #
    # Voice0  -> MIDI 48
    # Voice1  -> MIDI 49
    # ...
    # Voice31 -> MIDI 79
    # ========================================================

    for voice_index in range(
        voice_count
    ):

        midi_note = (
            48 +
            voice_index
        )

        target = midi_frequency(
            midi_note
        )

        # ====================================================
        # Search the local spectral peak around target.
        #
        # With 48000 samples:
        #
        # FFT resolution = 1 Hz
        #
        # ±3 Hz is sufficient.
        # ====================================================

        search_tolerance = 3.0

        mask = (
            (
                frequency >=
                target - search_tolerance
            )
            &
            (
                frequency <=
                target + search_tolerance
            )
        )

        local_frequency = (
            frequency[mask]
        )

        local_magnitude = (
            magnitude[mask]
        )

        if len(local_frequency) == 0:

            print(
                f"{midi_note:4d} "
                f"{target:11.3f} "
                f"{'---':>14} "
                f"{'---':>11} "
                f"{'---':>10} "
                f"FAIL"
            )

            all_pass = False

            detected_results.append(
                (
                    midi_note,
                    target,
                    None,
                    None,
                    None,
                    False
                )
            )

            continue

        # ====================================================
        # Find strongest FFT bin in local search window
        # ====================================================

        max_index = np.argmax(
            local_magnitude
        )

        detected = (
            local_frequency[
                max_index
            ]
        )

        detected_mag = (
            local_magnitude[
                max_index
            ]
        )

        frequency_error = abs(
            detected -
            target
        )

        relative = (
            detected_mag /
            global_max
        )

        # ====================================================
        # Validation conditions
        #
        # 1. Frequency error <= 2 Hz
        #
        # 2. Magnitude >= 10% of strongest detected component
        #
        # The magnitude condition prevents random FFT leakage
        # from being regarded as a valid Voice.
        # ====================================================

        frequency_pass = (
            frequency_error <= 2.0
        )

        magnitude_pass = (
            relative >= 0.10
        )

        passed = (
            frequency_pass and
            magnitude_pass
        )

        if not passed:
            all_pass = False

        detected_results.append(
            (
                midi_note,
                target,
                detected,
                frequency_error,
                relative,
                passed
            )
        )

        print(
            f"{midi_note:4d} "
            f"{target:11.3f} "
            f"{detected:14.3f} "
            f"{frequency_error:11.3f} "
            f"{relative:10.3f} "
            f"{'PASS' if passed else 'FAIL'}"
        )

    # ========================================================
    # Result
    # ========================================================

    print()

    if all_pass:
        print(
            f"{voice_count} VOICE FFT TEST PASS"
        )
    else:
        print(
            f"{voice_count} VOICE FFT TEST FAIL"
        )

    # ========================================================
    # Spectrum plot
    # ========================================================

    plt.figure()

    plt.plot(
        frequency,
        magnitude
    )

    plt.xlim(
        100,
        850
    )

    plt.xlabel(
        "Frequency (Hz)"
    )

    plt.ylabel(
        "Magnitude"
    )

    plt.title(
        f"{voice_count}-Voice TDM Synthesizer Spectrum"
    )

    plt.grid()

    return all_pass


# ============================================================
# Run 8-Voice test
# ============================================================

pass_8 = analyze_case(
    "poly32_8voice_pcm.txt",
    8
)


# ============================================================
# Run 16-Voice test
# ============================================================

pass_16 = analyze_case(
    "poly32_16voice_pcm.txt",
    16
)


# ============================================================
# Run 32-Voice test
# ============================================================

pass_32 = analyze_case(
    "poly32_32voice_pcm.txt",
    32
)


# ============================================================
# Final result
# ============================================================

print()
print("=" * 72)
print("FINAL RESULT")
print("=" * 72)

if (
    pass_8 and
    pass_16 and
    pass_32
):
    print(
        "POLY SYNTH CORE 32 FFT TEST PASS"
    )
else:
    print(
        "POLY SYNTH CORE 32 FFT TEST FAIL"
    )


# ============================================================
# Display all spectrum figures
# ============================================================

plt.show()