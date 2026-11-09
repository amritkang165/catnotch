# Rewrite CatNotch as a native macOS app, replacing Electron

Status: accepted

CatNotch is an Electron and Next.js app that already leans on a Swift helper, a MediaRemote adapter and a native glass module. We decided to rewrite it as one Swift app (SwiftUI inside an `NSPanel` per display) to cut idle memory and CPU, get real glass and animation, and drop the Electron, helper and IPC stack. It is a full rewrite with feature parity and no cuts, not a hybrid: keeping Electron as the shell would keep every cost we are trying to remove.

## Settled constraints

- Apple Silicon only, macOS 14 and up. Liquid Glass is used where available (macOS 26).
- Plain Xcode project in `macos/` while Electron still lives at the repo root, then moved to the repo root at cutover. Built with `xcodebuild`. Unsandboxed, ad hoc signed, not notarized, shipped through GitHub Releases and Homebrew only (private MediaRemote, `~/.claude` access and the keychain rule out the sandbox and the App Store).
- Renamed to CatNotch throughout: bundle ID `com.thecharydev.catnotch`, support folder `CatNotch`, store `catnotch-store.json`. The first launch imports once from the old `DeskNotch` folder. Permissions are asked for again once.
- The first native Release is 2.0.0, a Bridge release published under the old `-universal-mac.zip` name and `latest-mac.yml` so installed 1.0.x apps can update to it. After that the app has its own user-triggered updater (no Sparkle).
- Electron stays on `main` and keeps shipping until a single cutover PR deletes it. Work before then only adds to `macos/`, one numbered spec per phase.
- Same Claude hook protocol and port range; the vendored mediaremote-adapter is kept as is.

## Considered options

- **Hybrid** (native pieces inside Electron): rejected, it keeps the Electron cost and adds a bridge.
- **Pure AppKit UI**: rejected, far more code for no gain over SwiftUI in an `NSPanel`.
