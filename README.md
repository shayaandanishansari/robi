# Robi

A Flutter app that gives Robi a face: an animated eye display driven by a live, voice-based conversation with Gemini, front-camera face tracking, and a BLE-connected pan/tilt servo that keeps Robi looking at you.

## What it does

- **Eyes** — an animated eye widget (`lib/ui/widgets`) renders Robi's expression and gaze.
- **Vision** — `VisionService` runs on-device face detection (Google ML Kit) against the front camera feed to track where the user is.
- **Voice** — `LiveGeminiService` streams audio to and from the Gemini Live API over a WebSocket for real-time conversation, with mic capture and playback handled by `flutter_sound`.
- **Servo tracking** — `ServoTrackingController` and `ServoBleService` talk to an ESP-based pan/tilt rig over Bluetooth LE, nudging it in 1° steps to keep Robi's head aimed at the tracked face.

## Getting started

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (SDK `^3.11.4`).
2. Install dependencies:
   ```
   flutter pub get
   ```
3. Create a `.env` file in the project root with your Gemini API key:
   ```
   GEMINI_API_KEY=your_key_here
   ```
4. Run on a connected device (camera, mic, and Bluetooth permissions are required):
   ```
   flutter run
   ```

## License

AGPL-3.0 — see [LICENSE](LICENSE).
