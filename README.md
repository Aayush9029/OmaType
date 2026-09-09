<p align="center">
  <img src="assets/icon.png" width="64" alt="OmaType">
</p>
<h2 align="center">OmaType</h2>
<p align="center">Fast, local voice typing for Omarchy.</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/3b5190e8-fe02-4225-9b77-f57c2127fe8d" width="100%" alt="Petal capsule interaction demo">
</p>

<p align="center">
  <img src="assets/omatype-recording-bar.png" width="24%" alt="Recording waveform">
  <img src="assets/omatype-waveform.png" width="24%" alt="Live dictation waveform">
  <img src="assets/omatype-processing.png" width="24%" alt="Processing helix">
  <img src="assets/omatype-hover.png" width="24%" alt="Stop and discard controls">
</p>

## Install

```bash
git clone --branch hybrid-hotkey https://github.com/Aayush9029/OmaType.git
cd OmaType
./install-omarchy.sh
```

Tap **Home** to start/stop. Hold for live dictation. **Delete** to cancel.

Click the microphone in the bar → **Settings** to change the hotkey and recording mode, then **Save and apply**. Home is mapped to **F13** by keyd, so keep F13 selected to use Home. **All settings…** opens the full configuration editor; you can also run `omatype configure`.

The installer sets up keyboard access for the active desktop session. If the shortcut stops responding, Settings shows whether keyboard access is missing.

Built on [Voxtype](https://github.com/peteonrails/voxtype). Design and demo from [Petal](https://github.com/Aayush9029/petal).
