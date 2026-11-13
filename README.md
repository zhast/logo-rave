# Logo Rave

**Make your MacBook’s glowing lid logo react to the sound around you.**

Play music, clap, or talk. Logo Rave uses the **built-in microphone** to make the lid logo brighten with louder sounds and fade in quieter moments. It lives in the menu bar, with no Dock icon.

## What you need

- A MacBook with a supported, illuminated lid logo. The app checks for the logo backlight hardware; it cannot light a logo that has no backlight.
- A built-in microphone and permission to use it.
- Xcode or the Xcode Command Line Tools to build the app.

The app’s deployment target is macOS 14 or later, but its lighting controls use private Apple APIs. Hardware and macOS compatibility are not guaranteed. The keyboard-isolation fix was checked on a MacBook running macOS 27.2.1.

## Build and open

```sh
git clone https://github.com/zhast/logo-rave.git
cd logo-rave
make
open "Logo Rave.app"
```

Allow microphone access when prompted. If needed, check **System Settings → Privacy & Security → Microphone**.

`make` creates and locally signs `Logo Rave.app` in the repository. This is a local build, not a notarized release. Quit other apps that control the lid light, such as [LogoLight](https://github.com/Ark0N/LogoLight), so they do not compete.

## Everyday controls

| To… | Do this |
| --- | --- |
| Open the panel | Click the Apple icon in the menu bar. |
| Turn the light off | Click the large Apple logo in the panel, or press **Space** while the panel is open. Microphone capture also stops. |
| Turn it back on | Click the logo or press **Space** again. |
| Close the panel | Click outside it. The app keeps listening and controlling the light. |
| Quit | Click **Quit** in the panel, or right-click the menu-bar icon and choose **Quit**. Normal logo lighting is restored. |

The on/off switch lasts for the current session. Quitting is different from turning the light off: quitting returns the logo to normal behavior.

## Audio and privacy

- **Built-in microphone only.** There is no input picker, and the app never falls back to a Bluetooth headset or another external microphone.
- It hears the room, not a direct feed of system audio. Music played through speakers can be heard; audio in headphones may not be.
- It measures sound level locally. It does not save recordings or upload microphone audio.
- The meter is a smoothed relative sound level, not a calibrated sound-pressure meter. The light follows loudness, not detected musical tempo.
- The Apple-shaped ripples are a visual effect in the panel.

## If something looks wrong

**“Starting built-in microphone…”**
Capture is warming up. The interface stays responsive while the audio engine starts.

**“Built-in microphone unavailable”**
Check microphone permission. The app retries the built-in input and recovers from audio-device changes; it will not silently choose another microphone.

**The panel moves, but the physical logo does not**
Check that your Mac has supported logo hardware and that no other app is controlling it. If the keyboard-isolation API is unavailable, Logo Rave leaves hardware lighting untouched rather than risk pulsing the keyboard.

**The keyboard backlight moves with the logo**
Use the latest build and quit any older copies. Logo Rave restores the keyboard’s display-awake state after each global logo fade command without changing your brightness, auto-brightness, or idle-dimming settings. This depends on private APIs and may need adjustment after a macOS update.

**The meter pulses regularly regardless of sound**
Make sure the app was not launched with the developer-only `--preview` flag. Quit it and open it normally. Preview uses synthetic pulses; it does not listen to the microphone.

## Development

```sh
make          # Build the app
make test     # Run simulated/regression checks; does not change lighting
make icon     # Regenerate the SF Symbols-based app icon
```

For Xcode, open `Logo Rave.xcodeproj`, select **Logo Rave → My Mac**, and run with **⌘R**. Quit an existing copy first. Debug builds include symbols and disable Swift optimization.

For UI-only synthetic testing without hardware writes:

```sh
open -n "Logo Rave.app" --args --simulate --preview
```

`--preview` alone **does control the physical logo**, so combine it with `--simulate` when you only want to test the interface.

The automated checks exercise audio-level math, stale-audio handling, light command planning and panel toggles. They do not replace testing the real microphone and backlights. For the keyboard fix, hardware checks included 1,000 PWM samples during logo pulses and eight light off/on cycles; the keyboard remained enabled, with at most a 0.00104 absolute PWM-duty change during the toggle test.

If the app exits unexpectedly, useful Xcode symbolic breakpoints are `-[NSApplication terminate:]`, `objc_exception_throw`, and `abort`. A normal termination is not necessarily a crash; inspect the caller stack before attributing the cause.

## License

[MIT](LICENSE).
