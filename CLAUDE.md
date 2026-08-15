# CLAUDE.md — Paratarot (formerly Ava Tarot)

Read this first in any new session. It reflects the current built state. For
the in-progress redesign (Layout/Slot/Session graph model, deck & modifier
mechanics), see `Meta/Reading-Model.md` and the Next Session Candidates
roadmap below — neither is built yet, both are the design this file's
"Current State" section will be rewritten against as each step lands.

---

## What This Is

A dual-view tarot reading table built in Godot 4, deployed as a browser app on
`avareads.com`. Ava (the controller) runs live readings; a client logs into
their own real account and sees a **controller-curated subset** of the
reading — not a full mirror — via a live, controller-owned ACL over a
realtime WebSocket sync. **It is a tool, not a game** — no interpretation
logic, just cards, a layout, and who's allowed to see/touch what right now.

This is a from-scratch rewrite (2026-08-08) of the original prototype. The
old Godot game logic (drag/flip/slot system, three layouts, reading history
UI) and its standalone Flask+WebSocket backend (anonymous guest-token URLs,
full unfiltered state mirror, its own separate login) are both retired —
see git history before `ae54139` for reference if a past pattern is worth
consulting, but nothing there should be built on directly.

---

## Current State (as of 2026-08-14)

**The 2026-08-08 baseline** (session start → deal → controller toggles
visibility/flip → client sees it → checkpoint on End Reading) **was verified
working end-to-end on avareads.com by hands-on testing.** Steps 1–4, 5
(piece 1 of 2), 6 (Traits half), and 7 of the `Meta/Reading-Model.md`
roadmap landed 2026-08-11 through 2026-08-13, deployed but not
interactively tested at the time. **The Layout editor and Traits manager
have since had real hands-on testing (2026-08-14)** — several real bugs
only surfaced that way and got fixed live: a squeeze bug that made the Add
Slot button, per-slot rows, and Client Access's checkboxes silently
near-unclickable (rows demanding more width than the panel's fixed 320px
had to give), the new-layout mod-mode flash, and the Traits section's
whole assignment UI got redesigned around what actually turned out to be
usable versus what looked reasonable on paper. Deal Loose/Modify Card's
connecting-line rendering specifically is still untested — it's the one
piece of new drawing code from the earlier batch nobody's looked at yet.

### What works
- Public-tier login (`client_test` account, role `public`) → auto-redirects
  to `/portal` → "Enter Reading" → client mode, no menus
- Controller login (admin/dev/user role) → dashboard → Paratarot card →
  controller mode with rollup side panel, **landscape base resolution
  (1920×1080, flipped from mobile-first 2026-08-11)** — matches Paradotz,
  browser/laptop is the primary control surface
- **Two-layer slots**: each slot has independent Vertical (primary) and
  Horizontal (crossing/modifier) card positions, crossed via rotation,
  each with its own ACL — not one card per slot anymore
- **Layout/Slot are real graph nodes** (`Layout → Slot → Vertical/Horizontal`
  in the `tarot-deck` graph, loaded live via `GET`/`PUT /graphs/tarot-deck` —
  the same generic endpoints Paradotz itself edits a graph through, no
  bespoke Paratarot endpoint). Layout section in the controller panel:
  select/create layouts, add/move (numeric x/y fields, no drag yet)/delete
  slots — every action is an immediate graph write, no separate save step.
  A default "Classic Simple" 3-slot layout self-bootstraps into the graph
  the first time it's empty.
- Right-click context menu per card (ported UI pattern from Paradotz's
  `Editor.gd`): Show/Hide, Turn (flip), Invert (upright/reversed)
- **Client picker required before Start Reading** — closed list of
  registered `public`-role accounts (`GET /auth/clients`), includes the six
  active, trait-seeded test personas (Eleanor Rigby, Billy Shears, Pamela
  Polythene, Martha Mydear, Rocky Raccoon, Michelle Mybelle — login
  `<name>`, shared password `paratarot-test`, `properties.is_test_persona`
  on their Client nodes)
- **Session is a real graph node** now, not just an in-memory WS routing
  session: `session_number` (global sequential), `instantiated_at`,
  `client_joined_at` (stamped once, first connection), `ended_at` (stamped
  on checkpoint) as fixed properties; `Session--FOR_CLIENT-->Client` written
  atomically at Start Reading. Session rollup now splits into two
  mutually-exclusive control groups (`ControllerPanel.set_in_session()`):
  out-of-session (client picker + Start Reading) vs. in-session (Record
  Scenario + End Reading). Record Scenario is a mid-session save — writes a
  Scenario, clears the table, leaves the Session open. End Reading
  diff-checks the closing placements against the last save
  (`last_saved_placements` in `Grant/server/api-service/main.py`) and skips
  a redundant Scenario write if nothing changed since the last Record.
- **Deck controls are real** (Step 4, done 2026-08-13): a persistent standing
  order (`_deck_order`, undealt cards only) replaces the old inline-shuffle
  stopgap. Reset (clears the table, returns dealt cards to the pool) /
  Reshuffle / Unshuffle (canonical order: Major Arcana 0–21, then
  Wands/Cups/Swords/Pentacles Ace–King) / Deal Next (fills the next empty
  layer in slot-creation order) / Deal to Slot (explicit slot+layer picker)
  / **Deal Loose** (untethered card, cascaded into a tray). Dealing is
  state-independent — works in or out of a session, and out-of-session
  dealing produces zero graph writes for free since Record Scenario/End
  Reading are already gated to in-session.
- **Modifier mechanic, right-click path only** (Step 5 piece 1 of 2, done
  2026-08-13): a loose card's context menu gets Turn/Invert/**Modify
  Card**/Clear Modifier — picks any other on-table card (slotted or loose)
  and writes a `MODIFIES` edge between the two at checkpoint, drawn on the
  table as a connecting line. **Drag-and-drop (path 2) is deliberately not
  built** — real mouse-drag input handling is the one class of change that
  can't be verified without hands-on testing, and this is a live tool; held
  back rather than shipped blind. Loose cards are controller-only for now —
  no ACL modeled for them yet, so `grant-api`'s `_filter_state_for_client`
  explicitly never sends `state.loose` to a client.
- **Layout switching mid-session auto-saves** (Step 7, done 2026-08-13):
  switching the active Layout (or creating a new one) while in a session now
  triggers the same mid-session-save mechanic as Record Scenario first if
  there are any cards on the table, instead of silently discarding them —
  matches Reading-Model.md's "a Layout switch is just another trigger for
  that mechanic, not a new one." Also resets `_deck_order` to canonical
  order on any switch ("reshuffles back to its ready state").
- **Traits manager** (Step 6, half done 2026-08-13, reworked 2026-08-14 per
  live feedback): the rollup is now two distinct control clusters, not one
  undifferentiated checkbox list against all 80 traits. **Vocabulary**: Add
  Trait (text field, unchanged) plus a new **Delete Trait** (dropdown over
  the full vocabulary + confirm-gated delete — cascades to remove the Trait
  node and every edge touching it, `HAS_TRAIT` from any client and
  `LOADS_ON` to its `OceanFactor` alike). **Client Traits**: its own client
  picker, deliberately independent from the Session section's (in-session,
  locked to that client via `_pending_client`; out of session, this
  picker — "who will the next reading be with" and "whose traits am I
  looking at" are different questions). Shows only the *assigned* traits
  as a short list, each with a Remove button, plus a dropdown (filtered to
  what the focused client doesn't already have) + Add button to attach
  more. No more scrolling through all 80 to find the handful someone
  actually has.
- **Modify Trait + a `note` property** (2026-08-14, same day follow-up):
  the vocabulary picker now has a Modify button alongside Delete Trait,
  opening an inline editor (name field + a multi-line note field) for
  respelling and free-text notes. `note` is registered as Paradotz's
  `"text_long"` property type directly in the graph's own `type_schemas`
  (`_ensure_trait_note_schema()` in Main.gd — a graph-level dict, not a
  separate file, verified against Paradotz's `GraphPanel.gd`/`NodePanel.gd`/
  `Editor.gd` rather than guessed), with `show_in_hover: true` so a
  non-empty note surfaces in Paradotz's own node tooltip and renders as a
  real multi-line field there, not a generic single-line freeform property.
  Idempotent — only actually writes the schema entry the first time.
- Rollups now start collapsed, in the order Session / Deck / Client Access /
  Layout / Traits (was Layout-first, always-expanded).
- Removed the per-item separator lines between slot rows and Client Access
  rows added in the layout-editor rework — they weren't earning their keep.
- **Deal to Slot only ever offers empty layers** (2026-08-14): filled ones
  drop out of the picker entirely instead of staying pickable and getting
  rejected by `_deal_into()`. Selection always lands on whatever's first in
  the filtered list, so dealing to it "advances" to the next open one for
  free — no separate advance-the-selection logic needed. Button reads "No
  unfilled slots" and disables itself once the layout is full.
- **Deal order is a real, editable per-layer field** (2026-08-14): a
  `deal_order` property lives on each Vertical/Horizontal layer node
  (`_create_slot_with_layers`, `_next_deal_order()` auto-assigns a sensible
  default), not derived from slot-creation order anymore. Editable via new
  V#/H# fields in the Layout editor's slot rows, committed together with
  x/y through the same "Save Layout" batch. Deliberately per-*layer*, not
  per-slot — a slot's own Vertical and Horizontal can land anywhere
  relative to each other in the sequence (e.g. slot1-V, slot2-V, slot1-H),
  which a single per-slot order number couldn't express.
  `_next_deal_target()` only offers a Horizontal layer once its own
  Vertical is filled, so an inconsistent order (H before its own V) never
  gets Deal Next stuck — it just skips that candidate until it's legal.
- **Slot objects, first pass** (2026-08-14, `Nodes/SlotVisual.gd` — new
  file): a slot's name label, both card layers, and a name sub-label under
  each are now children of one node per slot instead of three independently
  drifting pieces (the name label used to be a bare sibling Label,
  repositioned only when `set_slots()` fully reran — which is why it used
  to snap into place after a drag/Save Layout instead of following it
  live; now moving the SlotVisual moves everything with it). Glow (radial,
  white by default, ~200px fade radius past the crossing pair's ~280×280
  footprint) and a halo ring (alpha 0 — nothing drives it yet, hook only)
  draw directly in the node's own `_draw()`, which puts them behind every
  child for free — no manual z-ordering. Both are `draw_circle`/`draw_arc`
  primitives deliberately, not `GradientTexture2D` — its exact fill API
  isn't grounded against any existing code in this repo.
  **Real card art now loads** (`CardNode.set_image()`, `Assets/Images/`,
  keyed off `Data/cards.json`'s `image` field — verified all 78 resolve to
  a real file before shipping this) — falls back to the name-text
  placeholder exactly as before when a texture can't load. Orientation
  needed no new code: the existing rotation system already flips a
  reversed card's whole render upside-down. A new sub-label under each
  layer shows what's placed there, `(inv)` suffix when reversed — **gated
  on `face_up`**, deliberately: the label must not leak a face-down card's
  identity to a client who can see a card is *there* (ACL "visible") but
  shouldn't know *what* it is yet. Tapping either card now also brings it
  to the top of local z-order (pure render-order swap, no data change) —
  default stack is Vertical behind, Horizontal in front ("closer to the
  user"). `CardWorld.apply_state()`/`_find_card_node()`/
  `_rebuild_modify_links()` all reworked around this — a slotted CardNode
  is now a grandchild (`CardWorld -> _world -> SlotVisual -> CardNode`),
  so the modify-link line math switched from `_world`-local position math
  to composed global transforms, which stays correct regardless of nesting.
  **Live-tuned twice, same day**: first look said the glow was too subtle
  once cards are in place (cards are fully opaque, so only the ring
  *outside* the card edges is ever visible — 200px only gave that ring
  ~20-60px of width). Bumped to 320px with a gentler falloff exponent
  (2.0→1.4). Second look said "much better" but rein in the full radius
  slightly — settled at 280/296/312 (glow/halo-inner/halo-outer). Texture
  loading and the z-order swap remain genuinely unverified.
- **Layout editor rearranged twice, same day**: Save Layout moved off the
  top Modify button (which now only ever enters mod mode) down to the
  bottom, next to Delete Layout — both are "I'm done with this layout"
  gestures. New **Rename** button next to Delete on the slot's name line —
  reveals an inline LineEdit + Save/Cancel in place, same pattern as
  Traits' Modify editor; only one slot can be mid-rename at a time.
  Numeric fields went through two passes: first, Order (V#/H# side by
  side) and Position (X/Y side by side) as two blocks with column headers
  above the whole list — then, per live feedback, the column headers
  ("not helping") came back out, and Order restacked *vertically* (V# then
  H# in the same narrow left column, "read down and see all of them along
  the left") while Position stayed side by side on the right, per the
  explicit ask. **New: a per-slot size slider** (`HSlider`, 0.5–2.0×,
  default 1.0) sits under the X/Y row, committed through the same Save
  Layout batch as everything else (a new `scale` property on the Slot
  node — `_on_slots_saved`/`_create_slot_with_layers`/`_parse_layouts` all
  touch it). Applied via plain `Control.scale` on the `SlotVisual` itself
  (`CardWorld.set_slots()`), pivoting around the crossing pair's center
  (`SlotVisual.pivot_offset`) rather than the slot's x/y origin, so
  resizing doesn't visibly shift the slot's table position — scales
  glow/halo/cards/labels together for free, no per-element scaling code
  needed. **Revised same day (0.13.1/0.13.2), per explicit feedback**
  ("I have to save the layout in order to see the results" / "the x/changes
  should show live too"): the slider and the X/Y fields now both preview
  live, before Save Layout. `ControllerPanel` gained
  `slot_scale_preview(slot_id, scale)` and
  `slot_position_preview(slot_id, x, y)` signals, wired in `Main.gd` to two
  new `CardWorld` methods, `preview_slot_scale()` and
  `preview_slot_position()` — both touch only the live `SlotVisual`
  (position/scale) and, for position, the mod-mode drag marker (skipped if
  that slot is the one actively being dragged, so the two don't fight).
  Neither writes to `_slot_geometry` or persists anything — the actual
  commit still only happens on Save Layout, same as before. The slider row
  also now shows a live `NN%` label next to it. Deal order (V#/H#) still
  has no live preview — not asked for. None of this (slider drag, X/Y
  live-preview, % label) is interactively verified — no browser access
  this session; only confirmed via a clean `deploy_paratarot.bat` export.
- Tap-to-flip: controller can flip any of its own cards directly; client can
  flip only a card the controller has currently granted the `flip` action on
- Live ACL: per-layer (not per-slot) visible/actions toggles in the Client
  Access rollup section, broadcast immediately over the WebSocket
- Reading checkpoint on End Reading: Scenario node, `Session--HAS_SCENARIO-->
  Scenario` and `Scenario--FOR_CLIENT-->Client` completing the triangle,
  PLACED edges from Scenario → each dealt card (carrying a `layer`
  property) — written through the same access-checked graph-write path
  every other Grant app uses, into the existing `tarot-deck` graph (grows
  in place, doesn't create a new graph per reading)

### What is not yet done (deliberately deferred, not forgotten)
- Card dragging / freeform placement (cards are still fixed to numeric-field-
  set positions or the Deck section's controls — see Step 5 piece 2 below.
  Slot dragging in the Layout editor's mod mode landed 2026-08-14, live at a
  computer with the user testing in real time, so the risk that held card
  dragging back doesn't apply the same way anymore — but it's a separate
  interaction with its own drop-resolution logic, not just "reuse the slot
  version," so still worth its own pass rather than assuming it's covered)
- Background (Step 6's other half) — per-Layout fill-color/image, not started
- Celtic Cross / Ava's Celtic Cross layouts (buildable now via the Layout
  editor, just not pre-seeded)
- `point` and `pick` ACL actions (protocol supports them; only `flip` is
  wired up client-side)
- Card info/meanings panel, reading history browser
- Card art on the table itself (deck data has `image` filenames in
  `Assets/Images/`, but `CardNode._draw()` currently only renders a
  placeholder + name text, not the actual card texture)
- Stats-model nodes as their own queryable type (reading metrics currently
  just live as empty properties on the Scenario node)
- Kuzu-as-primary-store migration on the Grant side (separate, near-term
  session — see `Grant/docz/infrastructure/data-architecture.md`) — until
  then, cross-reading trend queries over many Scenario nodes are JSONB-blob
  full-loads, fine at current scale, not built yet anyway

---

## Repo Layout

```
ava_tarot/
├── CLAUDE.md                  ← you are here
├── project.godot              ← Godot 4, GL Compatibility, 1920×1080 (landscape, browser-first,
│                                  flipped 2026-08-11 from mobile-first 1080×1920 — laptop browser
│                                  is the primary control surface, mobile secondary), canvas_items stretch
├── export_presets.cfg         ← Web preset; thread_support off, no COOP/COEP required
├── Autoloads/
│   └── ApiClient.gd           ← REST (idiom mirrored from Paradotz's GraphStore.gd) + WebSocketPeer
│                                  connection to grant-api's /ws/paratarot/{session_id}
├── Scenes/
│   ├── Main.tscn               ← entry scene, just a Control root + script
│   └── Main.gd                 ← orchestrator: mode detection from /auth/me, controller and
│                                  client setup/logic both live here
├── Nodes/
│   ├── CardNode.gd             ← single card: face up/down _draw(), tap-to-act, no drag yet
│   └── CardWorld.gd            ← the card table; pan/zoom container technique ported from
│                                  Paradotz's Editor.gd (not wired to input yet — not needed
│                                  for one fixed 3-slot layout that fits on screen)
├── UI/
│   ├── ControllerPanel.gd      ← rollup-panel pattern ported from Paradotz's GraphPanel.gd;
│   │                              Layout / Session / Deck / Client Access sections
│   └── ClientOverlay.gd        ← no menus — bottom action bar, only shows currently-granted
│                                  actions for the tapped card
├── Cards/
│   ├── Major Arcana/          ← 22 vault .md files (MA-00 through MA-21) — data, not code
│   └── Minor Arcana/          ← 56 vault .md files across 4 suits — data, not code
├── Data/
│   └── cards.json             ← 78 nodes, 286 edges — source of truth the Godot app reads at runtime
│                                  (layouts.json retired 2026-08-11 — Layout/Slot are real graph
│                                  nodes now, loaded live from tarot-deck via GET/PUT /graphs/,
│                                  same generic endpoints Paradotz itself edits a graph through)
├── Meta/                      ← Card-Schema.md, Graph-Index.md, Edge-Types.md, Reading-Model.md
│                                  (vault documentation, unchanged by the rewrite)
├── Assets/Images/             ← 78 card PNGs + card_back_default.png (not yet drawn on the table)
├── tools/
│   └── fetch_rider_waite.py   ← card-art fetch utility (kept; generate_readings.py retired,
│                                  was tied to the old JSON reading format)
└── deploy/
    └── deploy_paratarot.bat   ← Godot headless export + scp to avareads.com's
                                   /var/www/grant/apps/paratarot/ (mirrors Grant's deploy.bat shape)
```

No `server/` — the old standalone Flask backend is gone. All data/realtime
plumbing goes through `grant-api` and `grant-auth` on avareads.com (see the
Grant repo's `docz/infrastructure/auth-service.md` and `data-architecture.md`).

---

## Key Architecture Decisions

| Decision | Detail |
|----------|--------|
| No bespoke backend | Talks to Grant's shared `grant-api`/`grant-auth`, same pattern as Paradotz — not a separate Flask service |
| Public role, real login | Client is a named account with role `public`, not an anonymous guest-token URL |
| Live, controller-owned ACL | Visibility + allowed actions per card are toggled in real time by the controller, not a fixed rule; server (`grant-api`) filters what each client receives, client never sees unfiltered state |
| Controller stays authoritative | Client sends `action` requests only; controller applies them and rebroadcasts `state` — no client-side state mutation |
| No per-move persistence | WebSocket relay is in-process/ephemeral; Postgres is only touched at explicit checkpoints (session save), via the same access-checked path every other graph write uses |
| One graph, grows in place | Reading data lands in the existing `tarot-deck` graph as Client/Scenario/PLACED nodes+edges, not a new graph per reading — keeps it one thing always open-able in Paradotz |
| Code-first UI, no hand-authored complex scenes | `ControllerPanel`/`ClientOverlay`/`CardWorld`/`CardNode` are all `class_name` scripts instantiated via `.new()`, not `.tscn` hierarchies — only `Scenes/Main.tscn` is a real scene file, kept to a single root node |
| Paradotz's web-export conventions carried over | GL Compatibility renderer, `canvas_items` stretch, MenuButton-only (not OptionButton), Latin-1/ASCII-only button text — all hard-won lessons from Paradotz's HTML5 export, not rediscovered here |

---

## Realtime Protocol (grant-api's `/ws/paratarot/{session_id}`)

Controller → server: `{"type": "state", "payload": {"layout", "cards": {slot_id: {deck_card_id, name, face_up, orientation}}}}`, `{"type": "acl", "payload": {slot_id: {"visible": bool, "actions": [...]}}}`, `{"type": "save", "payload": {"client", "scenario", "placements"}}` (checkpoint).

Server → client: `{"type": "state", "payload": {...filtered...}, "acl": {...}}` — cards not currently `visible` are simply absent from `payload.cards`.

Client → server: `{"type": "action", "card_id": slot_id, "action": "flip"}` — server validates against the live ACL before forwarding to the controller; controller decides how to apply it (currently: flip toggles and rebroadcasts).

Server → controller: `{"type": "client_joined", "user_id", "username"}` when a client connects — this is how the controller knows who to attach to the Client node at the next checkpoint.

Full endpoint/session-store detail lives in `Grant/server/api-service/main.py`'s "Paratarot realtime sessions" section.

---

## Godot / Web-Export Gotchas Carried Over From Paradotz

- **MenuButton, never OptionButton** — the expand-arrow icon is a theme resource that fails to load in HTML5 exports.
- **Button text must be Latin-1/ASCII only** — Unicode dingbats render as placeholder boxes in the embedded web font.
- **`thread_support=false`** in the export preset, deliberately — no SharedArrayBuffer needed for a card table, which means no COOP/COEP headers required on the nginx side either (simpler than Paradotz's deployment in this one respect).
- **Self-modifying deploy scripts**: `update.sh`/`setup-site.sh` on the server do `git pull` on themselves mid-execution — bash keeps running the buffered pre-pull version for that invocation. First run after a script change won't apply the change; run it once more.

---

## Versioning

`const VERSION` in `Scenes/Main.gd`, shown in the controller panel (top of
`ControllerPanel`, via `set_version()`). Added 2026-08-11, same convention as
Paradotz's `MainMenu.gd` — bump on every commit that touches this repo's
source; it's the only way to confirm a deploy actually took effect in the
browser. Also added 2026-08-11: `/paratarot/`'s nginx location was missing
the `Cache-Control: no-cache` header `/paradotz/` already has for the exact
same reason (Godot reuses `index.js`/`.pck`/`.wasm` filenames on every
build, so browsers silently serve a stale cached copy after a deploy) — this
had been live and un-fixed since Paratarot shipped.

---

## Deployment

`deploy/deploy_paratarot.bat` — headless Godot Web export, `scp` to
`avareads.com:/var/www/grant/apps/paratarot/`. Reminder printed at the end:
if this is the first deploy after a Grant-side change (auth-service, nginx,
grant-api), also run `bash /opt/grant/server/scripts/update.sh` on
avareads.com and confirm `/etc/grant-site.env`'s `SITE_APPS` includes
`paratarot`. Per the Hub/Satellite rule, this app's source stays in this
repo — avareads.com only ever receives the built export, same shape as
Paradotz, just without centralizing the source in Grant since no second site
needs it (yet).

---

## Next Session Candidates

**Build roadmap, agreed 2026-08-10** — full design in `Meta/Reading-Model.md`
(Layout/Slot/Session/Client/Trait/Background graph model, deck & modifier
mechanics, controller panel structure). Ordered by actual dependency, not
importance — the hard spine is 1 → 2 → 3 → 5 → 7; Steps 4 and 6 are
pluggable wherever convenient once their own prerequisites are met.

1. ~~**Two-layer slot rendering**~~ — done 2026-08-11.
2. ~~**Layout/Slot as real graph nodes**~~ — done 2026-08-11, reworked
   2026-08-14 per live feedback. `Data/layouts.json` retired. The panel now
   starts on a plain dropdown + "Modify" button, not the slot-editing
   furniture — picking "+ New Layout" reveals an inline name prompt rather
   than creating anything immediately, and submitting it auto-enters
   modification mode. Only in mod mode do the slot list, Add Slot fields,
   and a confirm-gated "Delete Layout" button appear (cascades: removes the
   Layout, every Slot under it, their Vertical/Horizontal layers, and all
   touching edges — same shape as slot deletion, one level up; re-bootstraps
   a default layout if that was the last one). Switching the dropdown
   selection while in mod mode exits it (discarding pending row edits — see
   below), so the Modify button never points at the wrong layout.

   **Follow-up fixes, same day, from live testing:** (1) entering mod mode
   for a brand-new layout used to flash the *previous* layout's slot list
   for a frame — the Create button called it synchronously, racing the
   async graph write. Main.gd now calls `_panel.set_layout_mod_mode(true)`
   itself, only after the new layout is genuinely active. (2) Per-row Save
   buttons are gone; the Modify button becomes **"Save Layout"** while in
   mod mode, and clicking it batch-commits every row's current x/y in one
   graph write via a new `slots_saved` signal, then exits mod mode. Drag
   still commits immediately per-drop, unchanged — this only affects the
   numeric-field path. (3) A new slot's default position moved off `(0,0)`
   (`DEFAULT_NEW_SLOT_POS := Vector2(300, 300)`) — `(0,0)` always landed
   behind the panel. (4) **The side panel + canvas layout was rebuilt**:
   they used to be `HBoxContainer` siblings, which resizes children off
   their *minimum* size — a wide rollup (Client Access) grew the whole
   panel past its intended width, which shifted where CardWorld's local
   coordinate origin actually landed on screen, which is the real reason
   `(0,0)`-ish slots ended up behind the panel. Ported Paradotz's
   `Editor.gd` technique instead: `Main`'s root `Control` holds the panel
   (wrapped in a `ScrollContainer`, horizontal scroll disabled so overflow
   clips instead of growing it) and CardWorld as plain siblings, each
   positioned by anchor/offset math (`Main.PANEL_W := 320.0`) rather than
   container auto-layout — the panel is now a hard 320px, period, and
   CardWorld starts exactly there and fills the rest, regardless of which
   rollups are open.

   The old always-visible x/y SpinBoxes are now
   supplemented by **real drag-and-drop**: in mod mode, CardWorld shows a
   bordered placeholder per slot that can be click-dragged directly on the
   table (press-then-track-via-`_input()`, since `gui_input` alone stops
   firing the instant the cursor leaves the control mid-drag — same
   limitation card-dragging will hit in Step 5 piece 2). Drops that would
   overlap another slot (10px horizontal buffer, 30px above for the label)
   snap back to the pre-drag position instead of clamping to a legal spot.
3. ~~**Session as a formal entity**~~ — done 2026-08-12, all 5 pieces:
   `display_name` + `seed-personas.js`/`activate-personas.js` (six active,
   trait-seeded personas — see Grant repo); the client picker in the
   Session section (`GET /auth/clients`, required before Start Reading);
   the Session graph node itself (`session_number`, three timestamps,
   `Session--FOR_CLIENT-->Client` written atomically at start,
   `client_joined_at` stamped once on first connect,
   `Session--HAS_SCENARIO-->Scenario` completing the triangle, `ended_at`
   stamped on checkpoint); the Session panel split (out-of-session Start vs.
   in-session Record Scenario/End Reading); and the diff-check-before-close
   logic (skips a redundant Scenario write if nothing changed since the
   last Record).
4. ~~**Deck controls + freeform out-of-session play**~~ — done 2026-08-13:
   persistent `_deck_order` (undealt cards only), Reset/Reshuffle/Unshuffle/
   Deal to Slot/Deal Next/Deal Loose. Out-of-session dealing already
   produces zero graph writes for free, from the schema itself (Record/End
   are the only checkpoint writers, both gated to in-session).
5. **Card dragging + loose cards + the modifier mechanic** — 1 of 2 paths
   done 2026-08-13: Deal Loose + "Modify Card" as the right-click alternate
   path (picks a target from a menu, writes `MODIFIES`, draws a connecting
   line). **Remaining: the three-way drag resolution**
   (empty→vertical / filled-vertical→horizontal / both-filled→
   highlight+`MODIFIES`) — deliberately held back from the piece above since
   real mouse-drag input handling can't be verified without hands-on
   testing on a live tool. Do this one with the user at a computer able to
   click through it, not unattended.
6. **Traits & Background** — both small, Tag-style managed lists,
   essentially independent of everything above. **Traits half done
   2026-08-13**: a Traits rollup (state-independent tier) checkbox-lists the
   vocabulary (already 80 live from seed-personas.js's OCEAN bank, including
   the `Trait--LOADS_ON-->OceanFactor` weighting — that part predates this
   UI and was already server-side, just unexposed until now) against
   whichever Client is in focus, toggling writes/removes
   `Client--HAS_TRAIT-->Trait` edges directly; a text field adds new Trait
   nodes. "Focus" = `_pending_client` in-session, else the Session section's
   own picker selection out of session, matching the doc's own phrasing.
   Not done: Background (per-Layout `Layout--USES_BACKGROUND-->Background`,
   fill-color swatch picker) — separate, unstarted.
7. ~~**Layout switching mid-session**~~ — done 2026-08-13: switching or
   creating a Layout while in a session auto-saves first (same mechanic as
   Record Scenario) if there are any cards on the table, then resets
   `_deck_order` to canonical order ("reshuffles back to its ready state").
   Out-of-session switching stays passive, unchanged.

**Also still open, unrelated to this sequence:**
- Draw actual card art in `CardNode._draw()` instead of the name-text placeholder
- `point`/`pick` client actions
- Reading history browser reading from the graph's Scenario nodes instead of a flat file
