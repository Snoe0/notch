# Releasing

Pushing a `v*` tag builds, signs, notarizes, staples, and publishes
`Notch.dmg` to a GitHub Release, via
[`.github/workflows/release.yml`](../.github/workflows/release.yml). The
workflow refuses to run without the six secrets below — it can never ship an
unsigned DMG by accident.

## One-time setup

### 1. Developer ID Application certificate

1. In Xcode → Settings → Accounts → your team → **Manage Certificates…**,
   click **+** → **Developer ID Application**. (Or create it at
   [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates).)
2. In Keychain Access, find the certificate (`Developer ID Application:
   Your Name (TEAMID)`), expand it to confirm the private key is attached,
   and export it as a `.p12`, choosing an export password.
3. Base64 the file for GitHub:

   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```

### 2. App Store Connect API key (for notarization)

1. [App Store Connect → Users and Access → Integrations → App Store Connect
   API](https://appstoreconnect.apple.com/access/integrations/api) → generate
   a **Team key** with the **Developer** role.
2. Download `AuthKey_XXXXXX.p8` (only downloadable once) and note the
   **Key ID** and the page's **Issuer ID**.

### 3. Repository secrets

GitHub → repo → Settings → Secrets and variables → Actions. Six secrets, all
required:

| Secret | Contents |
| --- | --- |
| `MACOS_CERT_P12` | base64 of the exported `.p12` (step 1.3) |
| `MACOS_CERT_PASSWORD` | the export password chosen in step 1.2 |
| `MACOS_SIGN_IDENTITY` | the certificate's full name, e.g. `Developer ID Application: Jane Doe (TEAMID123)` |
| `APPLE_API_KEY` | the contents of `AuthKey_XXXXXX.p8`, pasted verbatim |
| `APPLE_API_KEY_ID` | the Key ID, e.g. `ABCD123456` |
| `APPLE_API_ISSUER_ID` | the Issuer ID (a UUID) |

## Cutting a release

Bump `CFBundleShortVersionString` in `Resources/Info.plist` if it changed,
then:

```bash
git tag v0.x.y
git push --tags
```

The workflow runs the tests, builds and signs the app, notarizes and staples
the DMG, verifies it with Gatekeeper, and publishes the DMG plus a SHA-256
`checksums.txt` to the release for the tag, with build provenance attested
via GitHub. A `workflow_dispatch` run from a branch exercises the same
pipeline without publishing.

## Local signed builds

The same scripts work outside CI for anyone holding the certificate:

```bash
SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID123)" ./Scripts/bundle.sh
SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID123)" ./Scripts/make-dmg.sh
xcrun notarytool store-credentials notch --key AuthKey.p8 --key-id ABCD123456 --issuer <uuid>
NOTARY_PROFILE=notch ./Scripts/notarize.sh
```

Without `SIGN_IDENTITY` the scripts behave exactly as before: ad-hoc signed
app, unsigned DMG.

## Fork safety

GitHub does not expose repository secrets to forks (or to pull requests from
them), so a fork running this workflow fails at the **Check release secrets**
step. Forks can only produce unsigned builds, or builds signed with their own
identity — never builds that verify as this project's owner.
