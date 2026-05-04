## ADDED Requirements

### Requirement: GitHub Releases publish self-update-compatible app assets
The GitHub Release workflow SHALL publish predictable app archive and checksum assets for each semantic release so the OpenMUX self-update command can verify and install the release without scraping release pages.

#### Scenario: App archive asset uses predictable name
- **WHEN** a tag named `v0.5.0` triggers the release workflow
- **THEN** the GitHub Release includes an app archive asset named `OpenMUX-0.5.0-macos-unsigned.zip`

#### Scenario: Checksum asset includes app archive entry
- **WHEN** the GitHub Release includes `OpenMUX-0.5.0-macos-unsigned.zip`
- **THEN** the GitHub Release includes `checksums.txt`
- **AND** `checksums.txt` contains a SHA-256 entry for `OpenMUX-0.5.0-macos-unsigned.zip`

#### Scenario: App bundle version matches release tag
- **WHEN** the app archive for tag `v0.5.0` is unpacked
- **THEN** `OpenMUX.app` has `CFBundleShortVersionString` equal to `0.5.0`
