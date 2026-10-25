# In-app updates

Settings → **Check for updates** queries the public `JoyceGu/td-capture` latest stable GitHub Release. There are no background checks, accounts or tokens. The version and integer build number are compared separately; the same version with a newer build is an update. GitHub release titles should include `build N` for same-version rebuilds (for example `TD Capture 0.5.0 (build 8)`).

A newer compatible release exposes **Download and install…**. The app validates GitHub's SHA-256 asset digest, ZIP paths, the application identifier, architecture, minimum macOS version, version/build and code signature. After verification, **Install and restart** saves pending library edits and backs up the notes library and the application's preferences. Recording, countdown, export, active scrolling and unsaved teleprompter changes defer installation.

A separate instance of the executable runs the installer only after the main app quits. It stages a replacement alongside the current bundle, keeps the previous bundle, and restores it if replacement or launch fails. An unwritable or translocated installation needs a manual move to a writable folder. The installer never replaces or migrates the existing notes/preferences directories. Recovery copies are kept in `~/Library/Application Support/TD Capture/UpdateBackups/`; temporary downloads are removed after a successful installation. Failed installations keep diagnostics and the old app.

The public ZIP is currently ad hoc signed and not notarized. The GitHub HTTPS response and its digest establish the expected download; ad hoc code-signature verification alone does not authenticate a publisher. macOS may require renewed recording permission after an ad hoc update. For a local Apple Development build, the installer reuses that exact existing signing certificate if available; it never creates or exports a private key. If that identity is unavailable, the old app is retained and a manual installation is needed.

The updater is included in 0.6.0 and later. Users on 0.5.0 or earlier must manually install 0.6.0 once before updating subsequent releases from Settings.

## Release requirements

- A stable, non-draft, non-prerelease GitHub Release with a numeric `vX.Y.Z` tag.
- An asset named `TD-Capture-X.Y.Z-macOS-arm64.zip` at that release's GitHub download URL.
- A SHA-256 `digest` in GitHub's asset metadata (GitHub computes it on upload).
- A ZIP containing `TD Capture.app` and optional `__MACOSX` metadata, with no symlinks, path traversal, encryption or ZIP64. This matches the current lightweight app bundle.
- Preserve `local.joyce.CameoStudio`, the existing notes directory and preference keys across updates.
- Increment `CFBundleVersion` and include the build in the release title when refreshing an existing version. A newer semantic version takes precedence over the build number.

Run `python3 Tests/test_updater.py --release-archive Releases/0.6.0/TD-Capture-0.6.0-macOS-arm64.zip` to check version ordering, release validation, checksum rejection, safe extraction, installed bundle validation, recovery after a launch failure and preservation of isolated user data. Tests do not install anything into Applications or modify actual scripts/settings.
