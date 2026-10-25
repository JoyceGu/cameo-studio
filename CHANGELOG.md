# Changelog

## 0.5.0

- Add free rectangular region recording with a normal-brightness selection and dimmed surroundings, without a colored border.
- Reuse effective screen recording permission for display and region selection; validate the actual capture filter and crop before accepting a source.
- Keep region guides, recorder controls and teleprompter out of captured video.
- Add recording controls for pointer highlighting, pen annotations, clearing ink and cursor-centered 3× zoom with global shortcuts enabled by default.
- Polish the watercolor setup screen and script library; show camera size as a percentage of the recording’s short edge and raise bottom-corner presets.
- Fix white horizontal artifacts during teleprompter scrolling.
- Prefer an available signing certificate for local builds to preserve identity across updates; the public ZIP remains ad hoc signed and not notarized.
- Add geometry and rendering checks for region selection.

## 0.4.0

- Add a persistent script library with multiple notes, title editing and legacy-script migration.
- Add TXT/Markdown file import and drag-and-drop, including UTF-8 and UTF-16 support.
- Bundle a local stdio MCP server with create/list/get/update/open/status tools and copyable configuration.
- Queue script activation while recording, exporting, scrolling or typing; preserve local edits on revision conflicts.
- Use English source strings, comments and filenames; move Chinese UI text into localization resources.
- Add protocol, persistence, concurrency and import validation tests.

## 0.3.1

- Rename the app to TD Capture across the interface, menus, exports, app bundle, assets and documentation.
- Rename the GitHub repository to `JoyceGu/td-capture`.
- Preserve the existing application identifier so saved scripts and preferences continue working.

## 0.3.0

Initial public release.

- Native screen/window recording with camera overlay and microphone audio, exported as MP4.
- Floating teleprompter with editable scripts, scrolling, text size and local persistence.
- English and Simplified Chinese interface switching in Settings.
- Adjustable camera background blur and three bundled background images, processed locally with Apple Vision.
- Watercolor application icon.
- Staged build and signature verification before application replacement.

Known limits: Apple Silicon / macOS 15+; ad hoc signing without notarization; microphone audio only; no recording pause; camera effects capped at approximately 15 fps.
