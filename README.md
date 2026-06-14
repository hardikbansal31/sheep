# Sheep — Software Requirements Specification (v3)

## 1. Introduction & Product Concept

Sheep is a lightweight, distraction-free digital notebook designed for rapid text entry and structured note organization. It balances the minimal, content-first aesthetic of Apple Notes with the structured hierarchy of Microsoft OneNote, without the bloat of either.

### Core Architectural Pillars

**Offline-First Performance:** The application operates entirely locally with immediate data accessibility. Network connectivity is treated as an asynchronous optimization layer rather than a system dependency. This applies equally to the web build, which uses service workers and IndexedDB via Drift's web backend — no internet required even on web.

**Structured Document Flow:** No infinite canvas. Content maps to a left-aligned fixed-width document body maximizing vertical screen real estate.

**Native Execution:** Built in Flutter, compiling directly to system hardware graphics APIs (Metal/Vulkan) for sub-50ms launch speeds and low idle memory footprints.

**JSON Document Model:** All note content is stored as a structured JSON document tree — not raw Markdown. This is the sole internal source of truth. Markdown is an import/export format only, never stored.

---

## 2. Information Architecture

### 2.1 Hierarchy

The app uses a flat two-level hierarchy:

```
Sections
  └── Pages
```

Notebooks are **out of scope for v1** and may be introduced in a future release. Sections are top-level. Every page belongs to exactly one section.

### 2.2 Empty State Policy

There is no empty state. The app always contains at least one section and one page. On first launch, "Section 1" and "Page 1" are created automatically. If a user deletes all sections, "Section 1" and "Page 1" are immediately auto-created before the deletion animation completes, so the app never renders an empty shell. This auto-creation also fires if the last remaining section is deleted via the confirmation dialog.

---

## 3. User Interface & Layout

### 3.1 Desktop Layout (Width > 760px)

Two-pane navigation + editor. Three columns total:

- **Left Pane — Sections Panel (240px fixed):** Lists all sections. Active section highlighted in accent color. Inactive sections in `--ink-primary`. Column header label "sections" in `--ink-secondary`. New section `+` button pinned to bottom of pane. App-wide search icon pinned to bottom-left corner of this pane.
- **Middle Pane — Pages Panel (300px fixed):** Lists all pages in the active section. Active page highlighted in accent. Inactive pages in `--ink-primary`. Column header label "pages" in `--ink-secondary`. New page `+` button pinned to bottom of pane.
- **Right Column — Editor Canvas:** Centered document body, fixed between 750px–800px width. Contains the thin top bar and the full-screen editor below it.

Both panes are individually collapsible for distraction-free writing.

### 3.2 Mobile Layout (Width ≤ 760px)

Linear stack navigation. Each level is a full screen:

```
Sections List → Pages List → Full-Screen Editor
```

Back navigation moves up the stack. No simultaneous pane rendering on mobile.

### 3.3 Top Bar (Editor Column Only)

A thin persistent toolbar scoped to the editor column only, flush with the top edge. Contains (left to right):

- Block type controls: Checklist, Bullet List, Numbered List
- Text style selector: Title, Heading 1, Heading 2, Subheading, Normal Text, Monospace, Code Block
- Font family selector
- Font size selector (numeric: 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 36, 48)
- Undo / Redo
- Insert Table
- Find & Replace icon

All icons and labels use Inter. The bar does not extend over the sections or pages panes.

### 3.4 Contextual Floating Toolbar

Completely hidden during normal writing. Appears floating above the cursor only when text is actively selected. Contains: Bold, Italic, Underline, Strikethrough, Hyperlink, Font Size, Text Color. Dismissed on click-away or selection collapse.

### 3.5 Context Menu

Triggered by right-click (desktop) or long-press (mobile) on any section or page list item. A simple elevated rectangle surface containing:

- **Rename**
- **Delete**

Uses `--surface-panel` background with a `--border` edge. No animations beyond a standard fade-in. Additional options (Move, Duplicate) may be added in future versions.

### 3.6 Section Deletion Confirmation

Deleting a section triggers a confirmation dialog (not a toast) since it cascades to all pages within it. Dialog text: *"Delete [Section Name] and all its pages? This cannot be undone."* Two actions: **Cancel** and **Delete**. Delete is styled in a destructive red, not the accent color. Page deletion (single page) uses a silent delete with a brief undo toast — no confirmation required.

### 3.7 App-Wide Search Overlay

Triggered by the search icon in the bottom-left of the sections pane, or a keyboard shortcut. Opens as a full-app centered modal overlay. Searches across all sections and pages simultaneously using FTS5. Escape or click-outside dismisses it. Styled like a command palette — single focused input, results list below.

---

## 4. Content Editor

### 4.1 Editor Engine

**AppFlowy Editor v6.2.0** — open-source Flutter rich text editor with a JSON-native document model. Pinned at exactly `6.2.0` in pubspec (not `^6.2.0`).

### 4.2 Block Types

Every piece of content is a typed block node in the JSON tree.

| Block Type | Description |
|---|---|
| `title` | Page title. One per page, always the first block. Rendered in Merriweather Bold, accent color. |
| `heading1` | Large section header |
| `heading2` | Medium section header |
| `subheading` | Small section label |
| `paragraph` | Standard body text |
| `bullet_item` | Unordered list item (nestable) |
| `numbered_item` | Ordered list item (auto-numbered) |
| `checklist_item` | Checkbox with `checked` boolean property |
| `code_block` | Monospace block with optional `language` tag |
| `quote_block` | Indented pull-quote |
| `divider` | Horizontal rule |
| `image` | Block-level image, capped to canvas width |
| `table` | Inline data table with internal horizontal scroll |

### 4.3 Block Node Schema

```json
{
  "id": "block_001",
  "type": "paragraph",
  "fontSize": 14,
  "fontFamily": "Inter",
  "children": [
    { "text": "Hello ", "bold": false, "italic": false },
    { "text": "world", "bold": true, "italic": false }
  ]
}
```

`fontSize` is an integer passed directly to Flutter's `TextStyle(fontSize: n)`. No encoding layer exists between the stored value and the renderer.

### 4.4 Special Block Behaviours

**Tables:** Columns exceeding 800px trigger a self-contained horizontal scroll view inside the table block. The main document width is never stretched.

**Images:** Stored as a file path or base64 string on the block node. Max width is canvas width. Resize handles available on selection.

### 4.5 Markdown Behaviour

Markdown is never stored. It exists only at the input/output boundary.

**Paste Interceptor:** Raw Markdown pasted via Ctrl+V / Cmd+V is parsed and converted to JSON block nodes on entry. The raw syntax never reaches the document tree.

**Live Token Expansion:** Typing a Markdown shortcut then a space (`# `, `## `, `- `, `1. `, `> `, `[] `) triggers an immediate block type conversion. The typed token is deleted and the block's `type` property is updated in the JSON tree. This is a keystroke handler, not a Markdown parser.

**Export to .md:** JSON tree serialized to standard Markdown. Properties with no Markdown equivalent (`fontSize`, `fontFamily`) are silently dropped. Disclosed in the export dialog.

**Export to PDF:** Full-fidelity. All block types, font sizes, and font families preserved at 1/72 inch point precision.

---

## 5. Typography System

### 5.1 Default Font Assignments

| Role | Default Font |
|---|---|
| Page Title (`title` block) | Merriweather Bold |
| Headings (`heading1`, `heading2`) | Inter Semibold |
| Subheading | Inter Medium |
| Body / Paragraph | Inter Regular |
| UI Labels (panels, timestamps) | Inter Medium |
| Code / Monospace | JetBrains Mono |

### 5.2 User Customization

All font family assignments are global defaults stored in the `UserPreferences` table. Users can override any role via Settings. A block node carries a `fontFamily` property only when the user has explicitly overridden the global default for that specific block. Otherwise it inherits from preferences.

### 5.3 Font Size

Numeric integers only. Stored on block nodes. Dropdown range: 10–48pt. A global `fontSize.default` preference sets the paragraph baseline (default 14pt). Blocks without an explicit `fontSize` inherit this value.

---

## 6. Themes

Three modes: **Light**, **Dark**, **System**. System follows OS preference via `MediaQuery.platformBrightnessOf`. Stored as the `theme` key in `UserPreferences` with values `light` / `dark` / `system`.

### 6.1 Light Theme

```
--surface-base:     #F9F8F5   main canvas background
--surface-panel:    #F0EDE8   sections + pages panes
--surface-hover:    #E8E4DE   list item hover
--ink-primary:      #1C1C1A   main text
--ink-secondary:    #6B6860   labels, timestamps, column headers
--ink-muted:        #A8A49E   placeholder text
--border:           #E2DDD7   dividers, pane edges
--accent:           #CC5500   active items, selections, title text
```

### 6.2 Dark Theme

```
--surface-base:     #1E1E1C   main canvas background
--surface-panel:    #252523   sections + pages panes
--surface-hover:    #2E2E2B   list item hover
--ink-primary:      #F0EDE8   main text
--ink-secondary:    #8A8680   labels, timestamps, column headers
--ink-muted:        #565350   placeholder text
--border:           #2E2E2B   dividers, pane edges
--accent:           #E8652A   active items, selections, title text
```

---

## 7. Spacing & Layout Constants

Base unit: **8px**. All padding, margin, and gap values are multiples of this unit: `4, 8, 16, 24, 32, 48`. No arbitrary values anywhere in the layout.

| Element | Value |
|---|---|
| Sections pane width | 240px |
| Pages pane width | 300px |
| Editor canvas width | 750px–800px (centered) |
| Top bar height | 40px |
| Mobile breakpoint | 760px |

---

## 8. Spell Check & Autocorrect

| Platform | Spell Check | Autocorrect |
|---|---|---|
| iOS | System keyboard (automatic) | Yes (system) |
| Android | System keyboard (automatic) | Yes (system) |
| macOS | Native macOS spell service via platform channel | No |
| Windows | None (v1 out of scope) | No |
| Linux | None (v1 out of scope) | No |

Custom dictionary additions on mobile hook into the OS dictionary. User-added words are also stored in a `custom_dictionary` SQLite table for future cross-platform sync. Incorrect words show an underline indicator on supported platforms. Corrected words show a brief visual confirmation indicator.

Autocorrect is mobile-only. No automatic word replacement on any desktop platform.

---

## 9. System Schema & Data Flow

### 9.1 Data Flow

```
Local User Input
       │
       ▼
[300ms Debouncer] ──► Local SQLite / Drift DB ──► PowerSync Engine ──► Cloud Sync Backend
                                                         ▲                (When Network Active)
                                                         │
                                                Local Device Cache
```

Auto-save fires only when the user pauses typing for 300ms. This decouples editor in-memory state from database I/O, preventing thread contention during active typing.

### 9.2 Relational Schema

```sql
CREATE TABLE Sections (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    order_index INTEGER NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Pages (
    id           TEXT PRIMARY KEY,
    section_id   TEXT REFERENCES Sections(id) ON DELETE CASCADE,
    title        TEXT NOT NULL,
    content_json TEXT NOT NULL,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE UserPreferences (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE CustomDictionary (
    word       TEXT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- FTS5 index over page content for sub-5ms search
CREATE VIRTUAL TABLE PagesSearch USING fts5(
    page_id,
    title,
    body_text  -- plain text extracted from content_json at write time
);
```

Note: `Notebooks` table removed. Sections are top-level in v1.

### 9.3 content_json Example

```json
[
  {
    "id": "b001",
    "type": "title",
    "children": [{ "text": "Q3 Planning Notes" }]
  },
  {
    "id": "b002",
    "type": "heading1",
    "children": [{ "text": "Goals" }]
  },
  {
    "id": "b003",
    "type": "paragraph",
    "fontSize": 14,
    "children": [
      { "text": "Increase retention by " },
      { "text": "15%", "bold": true }
    ]
  },
  {
    "id": "b004",
    "type": "checklist_item",
    "checked": false,
    "children": [{ "text": "Review onboarding funnel" }]
  }
]
```

---

## 10. Package Dependencies

| Package | Version | Purpose |
|---|---|---|
| `appflowy_editor` | 6.2.0 (pinned) | Core rich text editor, JSON-native |
| `flutter_riverpod` | latest stable | State management, scoped rebuilds |
| `drift` | latest stable | Type-safe SQLite ORM |
| `sqlite3_flutter_libs` | latest stable | Native SQLite binaries, all platforms |
| `powersync` | latest stable | Cloud sync layer over Drift |
| `path_provider` | latest stable | Platform-correct DB file path |
| `google_fonts` | latest stable | Merriweather, Inter, JetBrains Mono |
| `file_picker` | latest stable | Image insertion, file import |
| `pdf` | latest stable | PDF export pipeline |
| `share_plus` | latest stable | Export/share on mobile |
| `window_manager` | latest stable | Desktop window controls |
| `flutter_animate` | latest stable | UI transition animations |
| `intl` | latest stable | Timestamp formatting |
| `uuid` | latest stable | Block/page/section ID generation |

---

## 11. Flutter Architecture Notes

- **State management:** Riverpod throughout. The three panes are independent widget trees with separate providers. Typing in the editor never triggers a rebuild in the sections or pages pane.
- **Selective subscriptions:** Use `.select` on providers to subscribe only to the slice of state a widget needs.
- **Repaint isolation:** `RepaintBoundary` wraps each pane to isolate GPU repaint layers.
- **List rendering:** `ListView.builder` only — never `ListView` with a children array.
- **Const widgets:** All static UI elements use `const` constructors to be skipped during rebuild cycles.
- **Editor state decoupling:** AppFlowy Editor holds its own in-memory `EditorState`. Riverpod mediates only the 300ms debounced save trigger. These two are never tightly coupled.

---

## 12. Platform Targets

| Platform | Renderer | Offline | Notes |
|---|---|---|---|
| macOS | Metal | Full |  |
| Windows | Direct3D / Vulkan | Full | |
| Linux | Vulkan | Full | Primary development target |
| iOS | Metal | Full | |
| Android | Vulkan / OpenGL ES | Full | |
| Web | CanvasKit / HTML | Full | Service Worker + Drift web backend |

---

## 13. Resolved Decisions

| Decision | Resolution |
|---|---|
| Storage format | JSON document tree |
| Markdown role | Import/export boundary only; never stored |
| Font size representation | Integer on block node → Flutter TextStyle directly |
| Font family per block type | Global defaults in UserPreferences; per-block override optional |
| Notebook hierarchy | Deferred to future scope; v1 is Sections → Pages only |
| Empty state | Does not exist; auto-create Section 1 + Page 1 always |
| Section delete UX | Confirmation dialog (cascade risk); page delete is silent with undo toast |
| Search UX | Full-app modal overlay, command-palette style |
| Spell check desktop | macOS only via platform channel; Windows/Linux out of scope for v1 |
| Autocorrect | Mobile only |
| Theme options | Light / Dark / System |
| Accent color | `#CC5500` light / `#E8652A` dark (burnt orange) |
| Title font | Merriweather Bold |
| Rich text engine | AppFlowy Editor 6.2.0 (pinned) |
| Web offline | Service Worker + Drift web backend; no internet required |

---
Phases
Phase 1 — Project Setup & Dependency Resolution

Create the Flutter project with all packages in pubspec.yaml
Resolve the AppFlowy Editor 6.2.0 dependency conflict
Set up the AppTheme class with all design tokens for both light and dark themes
Set up the Drift database with the full schema above
Set up Riverpod (ProviderScope at root)
Verify flutter pub get and flutter run succeed with zero errors
No UI beyond a blank scaffold at this stage

Phase 2 — Layout Shell

Build the two-pane desktop layout: Sections pane (240px) + Pages pane (300px) + Editor column (remaining width)
Each pane wrapped in RepaintBoundary
Panes are collapsible
Mobile breakpoint at 760px — below this, render a linear stack navigator (Sections → Pages → Editor)
Column header labels ("sections", "pages") in --ink-secondary
Static placeholder content only — no database wiring yet
Pinned + button at the bottom of each pane
Search icon pinned to bottom-left of sections pane
Top bar in editor column (placeholder icons only)
No functionality yet — layout and theming only

Phase 3 — Database & Repository Layer

Implement full Drift DAO for Sections, Pages, UserPreferences, CustomDictionary
Implement the FTS5 PagesSearch sync (update the FTS index whenever a page is saved)
Implement the empty state auto-creation logic in the repository layer
Implement Riverpod providers: sectionsProvider, pagesProvider(sectionId), activePageProvider, activeSectionProvider
Wire sections list and pages list to their providers using ListView.builder
No editor wiring yet

Phase 4 — Editor Integration

Integrate AppFlowy Editor 6.2.0 into the editor column
Wire activePageProvider to load content_json into an EditorState
Implement the 300ms debounced auto-save (editor state → JSON → Drift)
Implement the plain text extractor that syncs body_text to PagesSearch on save
Ensure editor rebuilds are fully isolated from pane rebuilds

Phase 5 — CRUD & Interactions

Create section (+ button → inline rename field)
Create page (+ button → inline rename field)
Rename section/page (context menu → Rename)
Delete section (context menu → confirmation dialog → cascade delete)
Delete page (context menu → silent delete + undo toast)
Active state highlighting (accent color on selected section and page)
Empty state enforcement (auto-create on last deletion)

Phase 6 — Top Bar & Formatting

Wire all top bar controls to AppFlowy Editor commands
Block type switcher (paragraph, heading1, heading2, etc.)
Font family selector
Numeric font size selector (10–48pt)
Undo/Redo
Insert Table
Contextual floating toolbar on text selection (Bold, Italic, Underline, Strikethrough, Hyperlink, Font Size)

Phase 7 — Search

App-wide search overlay (full-app modal, command-palette style)
FTS5 query against PagesSearch
Results show page title + section name + snippet
Clicking a result navigates to that page
Escape or click-outside dismisses

Phase 8 — Settings & Themes

Settings screen: theme selector (Light / Dark / System), font family defaults per block type, global font size baseline
Persist all settings to UserPreferences table
Theme switching live without restart
System theme follows MediaQuery.platformBrightnessOf

Phase 9 — Export

Export page to .md (lossy — fontSize and fontFamily dropped, disclosed in dialog)
Export page to PDF (full fidelity)
Share via share_plus on mobile

Phase 10 — Polish & Platform

Desktop window controls via window_manager
Mobile spell check and autocorrect (iOS/Android system integration)
macOS spell check via platform channel
Markdown paste interceptor (Ctrl+V raw Markdown → JSON block conversion)
Live Markdown token expansion (#  → heading1, -  → bullet, etc.)
Performance audit: verify no cross-pane rebuilds using Flutter DevTools
Final spacing and color pass against design tokens

