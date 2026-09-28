# Third-party notices

## LidAngleSensor

The HID matching strategy and feature-report format used by `LidAngleSensor.swift` are based on:

- Project: LidAngleSensor
- Author: Sam Henri Gold
- Source: https://github.com/samhenrigold/LidAngleSensor
- License: Apache License 2.0

No audio assets or interface code from that project are included in MacDuo.

## SkyLightWindow — experimental lock-screen probe

The private SkyLight space-creation and window-delegation sequence in
`Sources/MacDuoSkyLight/SkyLightBridge.swift` is adapted from
[SkyLightWindow](https://github.com/Lakr233/SkyLightWindow), Copyright (c) 2025
Lakr Aream, under the MIT License. MacDuo adds symbol checks, error handling,
cleanup, passive windows, and a bounded diagnostic lifecycle.

The complete notice is in `Resources/Licenses/SkyLightWindow.txt` and is included
in both application bundles. The main app uses this bridge to present the
desktop Metal window and the separate lock-screen experiment.

## Private Core Animation runtime references

The backdrop and mesh adapters are independently implemented runtime bindings;
no external mesh library is bundled. The undocumented vertex/face layout and
the use of a mesh on a backdrop layer were checked against these primary references:

- [Bartosz Ciechanowski: Mesh Transforms](https://ciechanow.ski/mesh-transforms/)
- [Telegram: MeshTransform.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/MeshTransform/Sources/MeshTransform.swift)
- [Telegram: LegacyGlassView.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/LegacyGlassView.swift)

These APIs are unsupported and version-sensitive. Their availability and visual
behavior must be checked on the target macOS version.

## iPhone Duo Animation reference

`Resources/DuoFold.metal` adapts the mipmapped bicubic blur and edge shading
from [iPhone Duo Animation](https://github.com/akashtdev/iphone-duo-animation/)
by Akash T (MIT License) for a horizontal MacBook hinge and a live desktop
texture. The full license is in `Resources/Licenses/iPhoneDuoAnimation.txt` and
is copied into the app bundle. No 3D model or image asset from that project is
bundled.
