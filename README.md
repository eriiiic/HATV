# HATV

Home Assistant companion for Apple TV.

## MVP direction

HATV is a native tvOS dashboard app built with SwiftUI and SwiftData. The app connects to an existing Home Assistant instance, lets the user pick a Lovelace dashboard, and then displays it in a clean full-screen kiosk-style experience.

Current MVP focus:

- connect to Home Assistant with a long-lived token
- persist the selected server and dashboard
- browse available Lovelace dashboards
- render a focused subset of Lovelace cards natively
- open camera feeds full screen
- trigger common Home Assistant actions and toggles

## Tech stack

- Swift + SwiftUI
- SwiftData
- Security framework for token storage
- AVKit for camera playback
- Home Assistant REST + WebSocket APIs

## Project structure

- `HATV/` app source
- `HATVTests/` unit tests
- `HATVUITests/` UI tests scaffold

## Verification

Validated with:

- `xcodebuild -project 'HATV/HATV.xcodeproj' -scheme HATV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project 'HATV/HATV.xcodeproj' -scheme HATV -destination 'id=151FF4D4-9DBD-4393-A875-BB3D4274933A' CODE_SIGNING_ALLOWED=NO -only-testing:HATVTests test`
