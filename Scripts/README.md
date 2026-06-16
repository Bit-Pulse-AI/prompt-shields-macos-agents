# Build + release scripts

These are the scripts referenced by the PRD tickets **PS-01** (DMG
installer) and **PS-03** (notarisation). They are **not wired into CI
yet** — they're the primitives your CI pipeline will call.

## Release flow end-to-end

```
xcodebuild archive         # produces Promptly.xcarchive
xcodebuild -exportArchive  # produces Promptly.app
./Scripts/build-dmg.sh     # produces Promptly-<version>-macos-<arch>.dmg
./Scripts/notarize.sh      # signs + notarises the DMG
gh release create          # uploads to GitHub
```

## One-time setup

### Apple Developer membership + certificates

1. Enrol at [developer.apple.com](https://developer.apple.com) ($99/year).
2. Download the **Developer ID Application** certificate from the
   Certificates tab and add it to Keychain.
3. Generate an **app-specific password** at
   [appleid.apple.com](https://appleid.apple.com) →
   Sign-In and Security → App-Specific Passwords.
4. Record your **Team ID** from developer.apple.com → Membership.

### `create-dmg`

```
brew install create-dmg
```

### DMG assets (gitignored)

Drop the following into `Scripts/dmg-assets/`:

| File | Spec |
|---|---|
| `background.png` | 580x400 px, navy/blue gradient per PS-01 AC. Retina `@2x.png` recommended alongside. |
| `volume-icon.icns` | Finder icon for the mounted DMG volume (optional but polished). |

The build script works without these — it'll just produce a plainer DMG.

## Environment variables

Export these before running `notarize.sh` (or set as GitHub Actions
secrets):

```bash
export PROMPTLY_DEV_ID_APPLICATION="Developer ID Application: Bit-Pulse AS (TEAMID1234)"
export PROMPTLY_APPLE_ID="developer@bit-pulse.ai"
export PROMPTLY_TEAM_ID="TEAMID1234"
export PROMPTLY_NOTARY_PASSWORD="abcd-efgh-ijkl-mnop"
```

## CI hookup (future)

A GitHub Actions workflow along these lines closes PS-03's last AC
(CI signs + notarises on every release):

```yaml
jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Import certificate
        uses: apple-actions/import-codesign-certs@v2
        with:
          p12-file-base64: ${{ secrets.APPLE_DEV_ID_CERT_P12 }}
          p12-password: ${{ secrets.APPLE_DEV_ID_CERT_PASSWORD }}
      - name: Build
        run: |
          xcodebuild archive ...
          xcodebuild -exportArchive ...
      - name: Package DMG
        run: ./Scripts/build-dmg.sh ./build/Promptly.app ${{ github.ref_name }}
      - name: Notarise
        env:
          PROMPTLY_DEV_ID_APPLICATION: ${{ secrets.APPLE_DEV_ID_APPLICATION }}
          PROMPTLY_APPLE_ID: ${{ secrets.APPLE_ID }}
          PROMPTLY_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          PROMPTLY_NOTARY_PASSWORD: ${{ secrets.APPLE_NOTARY_PASSWORD }}
        run: ./Scripts/notarize.sh ./dist/Promptly-*.dmg
```
