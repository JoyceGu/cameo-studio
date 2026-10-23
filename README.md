<p align="center"><img src="Assets/TDCapture-watercolor.png" width="128" alt="TD Capture watercolor icon"></p>

# TD Capture

A native macOS recorder that combines your screen, camera and microphone into one MP4, with a floating teleprompter that stays out of the recording.

**Apple Silicon · macOS 15+ · English / 简体中文 · Local processing**

[Download the latest release](https://github.com/JoyceGu/td-capture/releases/latest) · [中文使用说明](USER_GUIDE.zh-CN.md)

## Features

- Record a display or an individual window, including browser and desktop apps.
- Open a floating recording control panel for pointer emphasis, drawing and 1×–3× zoom around the cursor; optionally enable global zoom/pen shortcuts.
- Composite your camera into the recording as a circle or rounded rectangle; adjust size, position and mirroring.
- Organize multiple scripts in a local library; import or drag in TXT/Markdown files.
- Let a local MCP-capable AI client create, update and open scripts without interrupting a recording. See [MCP setup](Docs/MCP.md).
- Read an editable, scrolling teleprompter with adjustable text size and speed. Pause scrolling or return to the top; scripts save locally.
- Keep the recorder controls, teleprompter and camera preview out of screen capture; the camera is added separately to the exported video.
- Choose the original camera background, adjustable background blur, or one of three image presets: Bright study, Soft nature and Soft watercolor.
- Switch between English and Simplified Chinese in Settings without restarting. Language and background choices persist.
- Export H.264 video and AAC microphone audio in an MP4. No account, API key or cloud processing required.

## Install

Download `TD-Capture-0.4.0-macOS-arm64.zip` from [Releases](https://github.com/JoyceGu/td-capture/releases), extract it and open **TD Capture.app**.

This is an early local prototype. The prebuilt app is ad hoc signed, **not Developer ID signed or notarized**, so macOS may prevent opening an Internet-downloaded copy. Building from source on your Mac is the alternative; the release is not an App Store distribution.

## Build from source

Install Apple's Xcode Command Line Tools, then:

```sh
git clone https://github.com/JoyceGu/td-capture.git
cd td-capture
./build.sh
open "TD Capture.app"
```

The script uses system Swift and frameworks only; there are no third-party dependencies. It creates an Apple Silicon binary targeting macOS 15+, signs it locally, and replaces the app only after compilation and verification. Quit any running copy before installing a new build.

## Record a video

1. Click **Choose a window…** and use the macOS window picker. For a full display, click **Record an entire screen…** and confirm the screen in the macOS system picker.
2. Choose your camera and microphone. Open the camera preview and allow camera access.
3. Set camera shape, position, size and mirroring. Use **Background…** to choose blur or a preset image.
4. Open the teleprompter, paste your script and adjust scrolling. Scrolling is controlled separately from recording.
5. Click **Start recording**, choose a new output filename, and allow microphone access if needed. Recording begins after a three-second countdown.
6. Click **Stop & export** and wait for the MP4 to finish. Finder reveals the saved file.

Use **Settings → Interface language** (⌘,) to switch languages. Permission settings are managed by macOS in System Settings → Privacy & Security.

## Scripts from AI clients

Open **Script library → Import via MCP → Copy connection configuration** and add the copied command to an AI client supporting local stdio MCP. The app does not modify client settings automatically. The tools can create/list/read/update notes, queue an open request and check its status; they never start recording. Setup, examples and limits: [Docs/MCP.md](Docs/MCP.md).

## Recording controls

Open **Recording controls…** at the top of the setup screen. Feature checkboxes and pen options appear first, followed by a **Keyboard shortcuts** section with the key guide; there are no mouse-operated zoom buttons. Normal mouse clicks do not change zoom. Pointer tracking adds a halo, emphasizes presses, and follows the pointer while zoomed. The pen draws on a transparent source-sized canvas; ink is included in the exported MP4. Turn the pen off to click normally in the source app, or use **Clear drawing** to remove all strokes. Drawing remains until cleared or the source changes.

Global shortcuts are enabled by default (and remember your choice). Use **⌘⌥ =** (jump to 3×), **⌘⌥ −** (return to 1×), **⌘⌥ 0** (reset), **⌘⌥ P** (toggle pen on/off), and **⌘⌥ K** (clear all drawing without changing pen mode). Zoom is limited to 1×–3× and applies to the exported recording; it does not magnify the live desktop. The camera overlay remains fixed. A floating badge shows the magnified state; returning to 1× shows a short confirmation. Pen mode adds a purple border, a faint tint, and a visible mode badge; drag inside the selected source to draw. Controls and the live annotation canvas are excluded from full-display capture; ink is composited separately. A selected single-window recording captures that window only.

Both window and whole-display selection use the macOS system picker. After display selection, TD Capture excludes its own windows and validates one real frame before accepting the source; the validation image is discarded. Selection failures show the actual error and preserve the previous source instead of repeatedly claiming the Settings permission toggle is off. macOS may still require an explicit sharing confirmation for the chosen source. Excluding recorder windows uses a separate filter and requires effective Screen & System Audio Recording permission; a picker grant alone is insufficient. If that stage returns `-3801` despite an enabled Settings switch after a local rebuild, remove the old TD Capture entry, add the current app, and relaunch if macOS requests it. The app checks the original picker filter first and reports which stage failed. Window-relative pointer and pen placement uses window metadata available on macOS 15.2 and later.

## Current limits

- Maximum output bounding box: 1920 × 1080, preserving the source aspect ratio; target screen rate: 30 fps.
- Blur and image replacement use Apple Vision person segmentation on the Mac. The processed camera rate is capped at approximately 15 fps. Hair, fingers and fast movement may have imperfect edges.
- Microphone recording only; system audio, recording pause/resume, separate camera tracks and automatic editing are not implemented.
- For individual-window recordings, use the corner presets for camera positioning. Dragging the preview uses display-relative coordinates.
- Protected content may not be capturable. Camera/microphone timing, Bluetooth and Continuity devices, multiple displays and fullscreen behavior should be checked with a short sample recording.
- Preview and exported video use the same processed camera image. A processing failure hides the untreated camera picture and shows a warning; choose Original background to disable the effect.

## Privacy

Camera, microphone, screen capture, background segmentation, encoding and settings storage run locally. The app has no upload or telemetry feature. Scripts are saved as local JSON documents under Application Support; preferences and an active-script compatibility/recovery backup use macOS UserDefaults. Configured MCP clients can read scripts through explicit tools; TD Capture itself does not upload them. The watercolor icon and preset background images were generated with ImageGen; the prompts are included under `Assets/`.

The application keeps its original internal bundle identifier for upgrade compatibility, preserving existing scripts and preferences. The displayed product name and executable are TD Capture.

## Source and validation

- `Sources/main.swift`: AppKit UI, language settings, camera/screen capture, teleprompter, compositor and MP4 writer.
- `Sources/Background.swift`: local person segmentation, background compositing and preset controls.
- `Sources/NoteStore.swift`: atomic note storage, revision checks, imports and persistent open requests.
- `Sources/NotesLibrary.swift`: script library, import UI and safe teleprompter handoff.
- `Sources/MCPServer.swift`: bundled local stdio MCP tool server.
- `Sources/Localization.swift` and `Resources/Localizations/`: English source strings with Chinese localization resources.
- `Info.plist`: application identity and camera/microphone permission descriptions.
- `Assets/`: app icon, bundled backgrounds and generation notes.

Verified on the development Mac: native build and signature validation; H.264/AAC export with 60 synthetic video frames and 60 audio buffers; camera-overlay pixel checks; real Vision segmentation on a generated test portrait; foreground preservation and all three background presets; UI language switching, persisted preferences and teleprompter scrolling. Test portraits, recordings and caches are excluded from this repository.

## 中文简介

TD Capture 可以同步录制屏幕、摄像头和麦克风，并合成为一个 MP4。附带不入镜的提词器、中英文切换、背景模糊和三张背景预选。所有处理在本机完成。

首次使用请允许屏幕录制、摄像头和麦克风权限，建议先录十秒样片。当前仅支持 Apple Silicon Mac / macOS 15+；发布包尚未经过 Apple 公证，也可通过 `./build.sh` 在本机编译。详细操作见[使用说明](USER_GUIDE.zh-CN.md)。

Code identifiers, comments, source strings and executable/script filenames are in English. Chinese interface text is maintained in localization resources. Protocol/storage tests: `python3 Tests/test_notes_mcp.py`; import tests: see [MCP development checks](Docs/MCP.md#development-checks).
