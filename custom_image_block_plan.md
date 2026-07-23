# Goal
Implement a custom image block for the editor that replaces the default AppFlowy image renderer. This custom component will solve the abrupt document jumping by using a better placeholder, introduce local image caching, and allow users to tap the image to open a full-screen, zoomable view.

## User Review Required
> [!IMPORTANT]
> **New Dependency**: We will need to add the `cached_network_image` package to `pubspec.yaml`. This is the gold standard for image caching in Flutter and handles local disk caching seamlessly.
> 
> **Placeholder Aspect Ratio**: Since we don't know the exact height of the image before it loads (unless it was previously resized and saved), I plan to use a 16:9 aspect ratio placeholder (or a fixed height like 250px) that fills the screen width. This will significantly reduce the "jumping" compared to the default 150px spinner. Are you okay with a 16:9 placeholder?

## Proposed Changes

### Dependencies
#### [MODIFY] pubspec.yaml
- Add `cached_network_image: ^3.3.1` to dependencies to handle image caching.

---

### Editor Core
#### [NEW] lib/features/editor/custom_image_block.dart
- Create `CustomImageBlockComponentBuilder` which implements AppFlowy's `BlockComponentBuilder`.
- Create the associated stateful widget to render the image.
- Use `CachedNetworkImage` to fetch and cache network URLs.
- Provide a `placeholder` widget that uses a soft grey background (using `colors.surfacePanel`) with a predefined height/aspect ratio to reserve space before the image loads.
- Wrap the rendered image in a `GestureDetector` that listens for `onTap`.
- Implement a full-screen route using Flutter's built-in `InteractiveViewer` (which supports pinch-to-zoom and panning) and a floating Close button.

#### [MODIFY] lib/features/editor/editor_pane.dart
- Import `custom_image_block.dart`.
- In `_rebuildEditorCaches()`, inject our custom builder into the `_cachedBlockBuilders` map by assigning `ImageBlockKeys.type: CustomImageBlockComponentBuilder(...)` to override the default AppFlowy image behavior.

## Verification Plan
### Manual Verification
1. Run `flutter pub get`.
2. Open the app and insert a new network image into the editor.
3. Observe the placeholder taking up space *before* the image fully loads, confirming the document doesn't jump wildly.
4. Tap the loaded image to verify it opens in a full-screen dialog.
5. Pinch to zoom and pan around the full-screen image using `InteractiveViewer`.
6. Go completely offline (turn off WiFi/Data), close the app, and reopen the document to verify `cached_network_image` successfully loads the image from the local cache.
