<p align="center">
  <img src="assets/icon.png" width="128" alt="OmaType">
  <h1 align="center">OmaType</h1>
  <p align="center">Fast local voice typing with tap-for-accuracy and hold-for-live dictation</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Aayush9029/OmaType" alt="License"></a>
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/Omarchy-native-111111" alt="Omarchy native"></a>
</p>

<p align="center">
  <img src="assets/omatype-panel.png" width="390" alt="OmaType transcript history panel for Omarchy">
</p>

OmaType is an Omarchy-focused fork of [Voxtype](https://github.com/peteonrails/voxtype). It keeps one lightweight Parakeet model warm and gives the Home key two jobs:

- **Tap** once to record, then tap again to process the complete buffer and type the more accurate transcript.
- **Hold** for two seconds to begin typing live, then release to stop.

Audio capture begins on the first key-down, so changing from tap to hold never drops the opening words.

## Install

On Omarchy:

```bash
git clone --branch hybrid-hotkey https://github.com/Aayush9029/OmaType.git
cd OmaType
./install-omarchy.sh
```

The installer builds the optimized binary, downloads and verifies the ~633 MB INT8 model, starts the user service, and adds the OmaType history panel to the Omarchy bar.

If Home is not already remapped by `keyd`, the installer prints the one-line mapping needed to keep the trigger from reaching focused applications.

## Usage

```text
Tap Home                        Start or finish an accurate batch recording
Hold Home for 2 seconds        Start live typing; release Home to finish
Delete                         Cancel the active recording
Left-click the bar icon        Open status and transcript history
Right-click the bar icon       Start or stop recording
```

The panel follows Petal's compact menu-bar flow in Omarchy's native visual language: current status first, recent transcripts below it, then recording controls. Click a transcript to copy it; use its trash action twice to confirm deletion.

```bash
omatype history list
omatype history list --json --limit 20
omatype history copy <id>
omatype history delete <id>
```

History contains transcript text and basic timing/model metadata only—never recorded audio—and stays at `~/.local/share/voxtype/history.json`. The newest 200 entries are retained.

The installed command and service are `omatype`; the internal data directory remains compatible with the upstream format.

## Credits

OmaType is built on Peter Jackson's MIT-licensed [Voxtype](https://github.com/peteonrails/voxtype), with the hybrid interaction, local history, and Omarchy shell experience maintained here.
