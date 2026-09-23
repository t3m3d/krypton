# Squirrel Sounds

Native SwiftUI iPhone/iPad app, iOS 17+. A squirrel sound-learning library that can expand to other animals.

## Open and run

Open `SquirrelSounds.xcodeproj`, select the SquirrelSounds scheme and an iPhone simulator, then Run. For a physical device, select your development team and choose a unique bundle identifier in Signing & Capabilities.

The project is generated from `project.yml` with XcodeGen (`xcodegen generate`).

## Implemented

- Data-driven species and recording library.
- On-device favorites, including an empty state.
- Local audio playback, pause/resume, scrubbing, elapsed time, and attribution.
- Playback pauses when the app becomes inactive, audio is interrupted, or headphones disconnect.
- Dynamic Type, semantic colors, VoiceOver labels, and iPad support.
- No account, server, tracking, microphone, or location permission.

## Recording still needed

The recording download was declined during development. No sound file is bundled, and the interface accurately shows “Recording not installed” with playback disabled.

To enable playback, obtain the gray squirrel recording linked in `SquirrelSounds/Resources/animals.json`, convert to MP3 if necessary, and save it as `SquirrelSounds/Resources/gray-squirrel-call.mp3`. Regenerate the project so the new resource is included. Keep the attribution, source link, CC BY-SA 4.0 license, and an accurate description of any changes. The recording is by Aubrey John Williams, copyright The British Library Board, shelfmark W1CDR0001470 BD12.

Do not replace this with an unrelated or synthesized recording described as authentic wildlife audio.

## Expansion

Add an animal to `animals.json` with a stable unique ID, name, scientific name, introduction, and sounds. Add each licensed audio file to Resources and regenerate the project. Recording IDs must be globally unique because favorites and playback use them. Existing screens render the expanded catalog automatically.

## Before App Store submission

Add and audition the licensed audio, create a production app icon, choose the final app name and bundle ID, configure signing, and test on physical iPhones (including interruption and headphone behavior). Publish a privacy/support page, prepare screenshots and App Store metadata, and complete the privacy questionnaire. This development build has not been submitted or approved.
