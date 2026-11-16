# Resources (not included)

The app's resources stay in the private repository and are not part of this public snapshot:

- `Assets.xcassets`: the cat, room and furniture artwork, and the app icon
- fonts and bedtime audio
- `Localizable.xcstrings`: the string catalog for English, Simplified Chinese, Traditional Chinese and Japanese

`project.yml` still lists this folder, so `xcodegen generate` needs it to build the app. The core package
in `Core/` does not use these files and builds and tests without them.
