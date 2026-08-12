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

## Current State (as of 2026-08-12)

**Deployed and verified working end-to-end on avareads.com.** The 2026-08-08
baseline (session start → deal → controller toggles visibility/flip → client
sees it → checkpoint on End Reading) still holds; Steps 1–2 and most of
Step 3 of the `Meta/Reading-Model.md` roadmap have since landed on top of it.

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
  atomically at Start Reading. Still missing: the Session panel split
  (Record Scenario vs. End Session) and diff-check-before-close — every End
  Reading today unconditionally writes a Scenario if there are any cards.
- Deal Three-Card: deals one vertical card per slot in the active layout
  from `Data/cards.json`, face-down, ~25% reversed (still a fixed "deal to
  every slot at once" button — real Deck controls are Step 4)
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
- Card dragging / freeform placement (cards and slots are both fixed to
  numeric-field-set positions; dragging is Step 5)
- Session as a formal graph entity, Client rename completeness (MBTI-style
  properties, `display_name`), Traits, Background, the loose-card/`MODIFIES`
  modifier mechanic — Steps 3, 5, 6 of the roadmap
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
2. ~~**Layout/Slot as real graph nodes**~~ — done 2026-08-11. Numeric x/y
   fields for now, not drag (that's Step 5). `Data/layouts.json` retired.
   Deletion now guarded by a `ConfirmationDialog` (ported from Paradotz's
   `NodePanel.gd:_on_delete_pressed` pattern); creating a new layout clears
   the table first. Follow-up noted, not yet done: hide the slot editor's
   x/y fields behind a "Modify" button (same button Step 5's drag will need
   anyway) instead of always-visible SpinBoxes — deliberately deferred to
   land alongside drag rather than build twice.
3. **Session as a formal entity**, plus `display_name` + the six test
   personas. 4 of 5 pieces done 2026-08-12: `display_name` +
   `seed-personas.js`/`activate-personas.js` (six active, trait-seeded
   personas — see Grant repo); the client picker in the Session section
   (`GET /auth/clients`, required before Start Reading); the Session graph
   node itself (`session_number`, three timestamps, `Session--FOR_CLIENT-->
   Client` written atomically at start, `client_joined_at` stamped once on
   first connect, `Session--HAS_SCENARIO-->Scenario` completing the
   triangle, `ended_at` stamped on checkpoint). Remaining: the Session panel
   split (out-of-session Start vs. in-session Record Scenario/End Session)
   and the diff-check-before-close logic — today End Reading always writes
   a Scenario unconditionally, there's no separate mid-session "Record and
   keep going" action yet.
4. **Deck controls + freeform out-of-session play** — persistent deck-order
   state, Reset/Reshuffle/Unshuffle/Deal to Slot/Deal Next/Deal Loose.
   Out-of-session dealing should produce zero graph writes for free, from
   the schema itself, not special-cased.
5. **Card dragging + loose cards + the modifier mechanic** — Deal Loose, the
   three-way drag resolution (empty→vertical / filled-vertical→horizontal /
   both-filled→highlight+`MODIFIES`), "Modify Card" as the right-click
   alternate path.
6. **Traits & Background** — both small, Tag-style managed lists,
   essentially independent of everything above.
7. **Layout switching mid-session** — restart-with-auto-save behavior; needs
   Step 2 (more than one real layout) and Step 3 (the save mechanic).

**Also still open, unrelated to this sequence:**
- Draw actual card art in `CardNode._draw()` instead of the name-text placeholder
- `point`/`pick` client actions
- Reading history browser reading from the graph's Scenario nodes instead of a flat file
