<p align="center">
  <img src="assets/icon.png" width="64" alt="OmaType">
  <h1 align="center">OmaType</h1>
  <p align="center">Fast local voice typing with tap-for-accuracy and hold-for-live dictation</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Aayush9029/OmaType" alt="License"></a>
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/Omarchy-native-111111" alt="Omarchy native"></a>
</p>

<p align="center">
  <img src="assets/omatype-panel.png" width="390" alt="OmaType transcript history panel for Omarchy">
  <br>
  <img src="assets/omatype-waveform.png" width="390" alt="OmaType floating live dictation waveform">
  <img src="assets/omatype-recording-bar.png" width="390" alt="OmaType batch recording bar with elapsed time and waveform">
</p>

## How it works

| Input | Result |
| --- | --- |
| Tap Home, then tap again | Record, process for better accuracy, and type at the cursor. |
| Hold Home for 2 seconds | Type live until Home is released. |
| Delete | Cancel the active recording. |

Recording begins on key-down, so a hold keeps the opening words. The floating bar shows mic activity, elapsed time, and processing; the menu-bar icon opens history and models.

## Install

On Omarchy:

```bash
git clone --branch hybrid-hotkey https://github.com/Aayush9029/OmaType.git
cd OmaType
./install-omarchy.sh
```

The installer builds OmaType, downloads the ~633 MB INT8 Parakeet model, enables its login service, and adds the Omarchy panel. It prints a `keyd` mapping if Home needs remapping.

## Models and history

| Model | Best for |
| --- | --- |
| Parakeet Live | Fast English tap and live dictation |
| Whisper Small | Accurate multilingual tap mode |
| SenseVoice Small | Lightweight Chinese, English, Japanese, Korean, and Cantonese |

Missing models download from the panel. The active model stays warm, and the newest 200 transcripts are kept locally without recorded audio.

## Credits

Built on Peter Jackson's MIT-licensed [Voxtype](https://github.com/peteonrails/voxtype).
