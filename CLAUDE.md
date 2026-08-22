# CLAUDE.md — Paratarot (formerly Ava Tarot)

Read this first in any new session. It reflects the current built state.
`Meta/Reading-Model.md`'s Layout/Slot/Session graph model and deck & modifier
mechanics — the redesign this file used to describe as "in-progress" — are
now fully built, including full client-side deck/loose/layout access
(2026-08-17). All 7 Next Session Candidates roadmap steps below are done;
Background's own half of Step 6 is the only piece of the original roadmap
still explicitly open — see "What is not yet done" for that plus everything
added to the list since. Read the roadmap section for the step-by-step
history and "Non-obvious bugs" for hard-won lessons before touching
drag/drop code.

**As of 2026-08-17, priorities have shifted toward launching the site as a
real business** (see Grant's own CLAUDE.md "Last Session") — this repo's
further feature work (Scenario-recording depth, weighted stats driving the
table's visual language, client worksheets) is real but explicitly lower
priority right now than getting avareads.com itself ready for paying
customers.

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

## Current State (as of 2026-08-17)

**The 2026-08-08 baseline** (session start → deal → controller toggles
visibility/flip → client sees it → checkpoint on End Reading) **was verified
working end-to-end on avareads.com by hands-on testing.** Steps 1–7 of the
`Meta/Reading-Model.md` roadmap are now all done and hands-on tested,
including Step 5's full drag-and-drop modifier mechanic (below) — the
whole roadmap that kicked off this rebuild is complete. Everything in this
section has been through live, interactive testing on avareads.com, not
just deployed-and-assumed — this project's hardest bugs (see "Non-obvious
bugs" at the bottom) only ever surfaced that way.

**2026-08-16 session, by far the largest single batch since the rebuild:**
real card drag-and-drop (Step 5's other half), a per-slot Horizontal on/off
toggle, live amber/green drop hints, an edge-drag rework of the right-click
modify flow, loose card labels, a whole new physical deck object with its
own hover/hold-to-draw gesture, and — the hard part — a genuine, fully
diagnosed root-cause bug hunt (not a workaround) that took many rounds of
live screenshots and a temporary on-screen diagnostic overlay to pin down.
See "Non-obvious bugs" below for the postmortem; it's worth reading before
touching any of `CardWorld._resolve_loose_drop()`/`_set_drag_hover()`.

**2026-08-17 session: first real client-side testing pass, ever.** Every
prior session had only hands-on-tested the controller. First finding:
Client Access "Visible" toggles did nothing on the client's screen — traced
via live `journalctl -u grant-api -f` log evidence to prove the server
pipeline (controller → ACL filter → broadcast) was already correct, which
narrowed it to the client. Root cause: the client's own `CardWorld` never
had any `SlotVisual` objects at all — `apply_state()` only ever renders
into `_slot_visuals`, which only `set_slots()` populates, and that call was
buried inside the *controller's* own layout-loading path
(`_apply_active_layout()`), never reached from `_setup_client()`. Not a
filtering bug, not a rendering bug — the client's table simply had zero
slots on it, so a perfectly correct payload had nowhere to go. Fixed by
having the controller carry slot geometry (position/scale/name/
horizontal-on) along in the same "state" WS push every other change
already triggers (`_state["slots"]`, set in `_apply_active_layout()`);
`grant-api`'s `_filter_state_for_client` forwards it unfiltered (structural,
not reading content — only card contents/visibility are ever ACL-gated).
The client had no other way to learn this: a `public`-role account has no
`graph_access` grant, so a direct `GET /graphs/tarot-deck` (the first fix
attempted) would have 403'd for a real persona even though it worked
conceptually. Confirmed fixed live. Same session, three more real
client-facing gaps closed once testing was actually possible: a client's
granted flip was a standing back-and-forth ability, not the intended
one-shot "let them turn this one over" (now auto-revoked on use, syncing
the controller's own checkbox); `_on_client_ws_closed()` cleared card data
on End Reading but never tore down the now-empty `SlotVisual` placeholders
themselves, so their outlines lingered on the client's screen indefinitely
(now `set_slots({})` alongside `apply_state({})`); and deck client access
("Piece B", deferred since 2026-08-16) shipped — see "What works" below.
Same session, second half: the deck's selection/resolution controls got
fully built out (Draw & Select/Select Loose, click-to-carry, place/free/
modify), Layout/Loose visibility with an off-cascade landed, a real
WS-connect race (`send_ws()` called before the socket had actually
opened) and a real session-retirement race (End Reading never told the
server the session was over, only an eventual disconnect did) were found
and fixed — the latter was the root cause of a "client sees a ghost of
the previous reading" report that looked client-side and wasn't. **This
closes out the session's Paratarot work** — priorities moved to launching
avareads.com as a real business (see intro above and Grant's own
CLAUDE.md), and this repo's next session likely starts from a business
need (Schedulez usage feedback, payment-field tweaks) rather than picking
the roadmap back up cold.

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
- **Payment fields on the Session node (2026-08-17)**: `payment_method`
  (Venmo/Cash/Other), `payment_amount`, `payment_waived` — low-tech and
  manual by design, matching where the business actually is right now (a
  Venmo personal-profile link, her own confirmation at session time, no
  processor integration — no LLC bank account yet, and Stripe/Venmo don't
  interface with each other regardless). New "Payment" controls at the
  bottom of the in-session Session rollup: a method dropdown, a `$` amount
  `SpinBox`, a "Waived" checkbox (disables the other two rather than
  leaving them at a misleading blank/zero), one "Save Payment" button — no
  live-push-per-keystroke like the ACL checkboxes elsewhere in this panel,
  deliberately, so a half-typed amount never gets written. New `"payment"`
  WS message type; writes straight onto the Session graph node
  server-side, the same direct-property-write pattern `client_joined_at`/
  `ended_at` already use — never part of `state`/`acl`, so it's never
  broadcast to a client. Fields reset to blank every time a session starts
  (no pre-fill from a prior reading).
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
- **Card dragging + the modifier mechanic, drag path (Step 5 piece 2, done
  2026-08-16):** dragging a loose card resolves live to one of three
  outcomes, matching `Meta/Reading-Model.md`'s design exactly — dropped on
  an empty Vertical → fills it; Vertical filled/Horizontal open → fills
  Horizontal; dropped on an occupied card → creates a `MODIFIES` edge to it.
  A live hover preview shows which outcome you're over *before* you
  release: green outline on the empty layer you'd fill, amber outline on
  the occupied card you'd modify — amber always wins over green when both
  could apply. Per live feedback, Horizontal's own footprint (wider than
  Vertical's, from the 90° crossing rotation) takes priority to fill it
  once Vertical is occupied — dragging to the middle of a partially-filled
  slot fills Horizontal by default, not the exception. When multiple slots'
  interactive footprints could plausibly apply to the same drop point
  (Horizontal's real 280px width exceeds the 180px anti-overlap spacing
  rule slots are only guaranteed apart by), resolution picks whichever
  slot's own pivot is physically closest to the point — see "Non-obvious
  bugs" below for why this needed several attempts.
- **Right-click "Modify Card" (Reading-Model.md path 1) reworked as an edge
  drag, not a text list (2026-08-16):** clicking it grabs the loose end of
  the would-be edge and lets it follow the mouse, with the same amber
  highlight the card-drag path uses picking out whatever's hovered (any
  on-table card, loose or slotted); the next click/right-click/Escape
  resolves or cancels it. The old list named every candidate card by name
  even face-down, which the new path never does.
- **Per-slot "Horizontal on" checkbox** in the Layout editor (structural
  `horizontal_enabled` Slot property, defaults true). Off means a filled
  Vertical reads as the whole slot being full: Deal Next/Deal to Slot/the
  drag-drop resolution all stop offering that slot's Horizontal, and
  dragging a loose card over the Vertical shows the modify highlight
  instead of falling into a Horizontal nobody wants used for that spread
  position.
- **Right-click "Remove from Slot"** on a slotted card — sends it back to
  loose (still a legitimate on-table card, not destroyed) rather than into
  the deck. A Vertical can't be pulled out from under a filled Horizontal;
  the menu omits the option in that case rather than showing and rejecting it.
- **Tap-to-reveal is one-way**, both for slotted and loose cards: a plain
  tap only ever turns a card face-up, never back down — turning it back
  over is a deliberate act via the right-click "Turn" menu. (Originally a
  bug report: tapping a card to switch which of Vertical/Horizontal was on
  top was also toggling it back face-down as a side effect.)
- **Loose cards show their own name label** below them once face-up
  (`(inv)` suffix when reversed), same idea as the slotted sub-labels but
  simpler — a plain child Label that travels with the card for free on any
  drag via Godot's own transform composition, counter-rotated so it stays
  upright and anchored below the card regardless of orientation.
- **A physical deck object (`Nodes/DeckVisual.gd`, 2026-08-16, controller-
  only)** — a small stack in the table's upper-right, draggable to
  reposition. Hovering with no button, or pressing and holding still, both
  "prime" it after 1s (highlight + a gentle top-card lift loop); from
  primed, any further motion or a release peels a card off and hands
  control to the same loose-card drag machinery above, already following
  the cursor — matches genre convention (iOS-style tap/long-press/drag,
  Solitaire/Tabletop-Simulator-style "drag off the stock pile to draw").
  Right-click menu: Deal Next, Deal Loose, Draw (menu-only shortcut to the
  same end state as the hold gesture, skipping the wait), Shuffle, Reset.
  The client-facing side of this — visibility, letting a client "pick" a
  card, separate place/modify permission bits — is a deliberately deferred
  follow-up piece needing its own client-role testing pass.
- **Deck client access, full (2026-08-17, built in two passes)**: a "Deck"
  cluster in Client Access, all sharing the `"_deck"`/`"deck"` pseudo
  slot_id/layer pair (deliberately, not a new ACL shape — reuses
  `actions_for()`/`sync_acl()`-style plumbing and the client
  action-request path, both grant-api's action validation and CardWorld's
  own resolution keying off card_id+layer generically, with no
  special-casing anywhere else in the pipeline) even though not everything
  in it is literally about the deck object. Two tiers:
  - **Selection methods** — how a card gets "into a client's hand," four
    checkboxes: **Can Deal Next**/**Can Draw Loose** (unchanged,
    server-authoritative one-tap deals — reuse
    `_on_deal_next_pressed()`/`_on_deal_loose_pressed()` verbatim, no
    session gating to route around, either one); **Can Draw & Select**
    (draws the same way as Draw Loose, then the instant the new card's
    real identity comes back in the next broadcast, the client calls
    `CardWorld.begin_loose_drag()` on it itself — see
    `Main._pending_draw_select`/`_last_loose_ids` diffing); **Can Select
    Loose** (shown on an *already-loose* card's own tap menu, not the
    deck's — picks it up the same way). The latter two are
    "selection-only": tapping either just picks a card up, it doesn't
    resolve anything by itself.
  - **Resolution methods** — once a card is selected and dragged, **Can
    Place in Slot** / **Can Place Freely** / **Can Modify** govern how the
    drop resolves (mirrors CardWorld's existing "place"/"modify"/
    "reposition" resolution kinds exactly — same highlights the controller
    sees). Never shown as buttons (`ClientOverlay` filters against an
    explicit per-context whitelist, not "whatever's in the ACL array") —
    they're outcomes of a drag, not commands. A resolution kind that isn't
    granted falls back to a fixed tray position instead of wherever the
    client actually dropped it (`"loose_fallback"`, auto-granted whenever
    any selection method is on, never a checkbox) — deliberately distinct
    from "place freely," so it reads as "not your call," and also the
    safety net if a permission is revoked mid-drag.
  - The pick-up gesture itself is **click-to-carry, not press-and-hold**:
    tapping "Draw & Select"/"Select Loose Card" calls
    `CardWorld.begin_loose_drag()` programmatically (sets `_loose_dragging
    = true` immediately, skipping the usual press-distance threshold), so
    the card follows the pointer with nothing held down until the next
    click resolves it — reuses the same mechanic `begin_edge_drag()`
    (Modify Card) already established, just applied to a card's position
    instead of an edge endpoint. A raw press-and-hold directly on an
    interactive loose card still also works (CardWorld's drag machinery
    doesn't care how a drag started), kept alongside rather than removed.
  - The client's action bar refreshes live now, not just on next tap —
    `_on_state_received` re-pushes whatever's currently open through the
    same whitelist every time a fresh state/acl arrives, so a permission
    toggled off while a menu is open doesn't leave stale buttons showing.
  - Client isn't authoritative, so a resolved drag becomes a request (the
    controller re-validates independently — `Main._apply_client_loose_resolution`
    — before touching state), same "client proposes, controller applies
    and rebroadcasts" pattern flip already used. Needed the action-relay
    to forward the *whole* message, not just card_id/layer/action/user_id
    (grant-api) — the resolution actions carry extra targeting fields
    (loose_id, slot_id, target_layer, target_card_id, x, y).
  - `point` and full free-form multi-touch dragging are still open — see
    below — but `pick` itself (a client actually selecting and placing a
    card, with real resolution permissions) is done.
- **"Show All"/"Hide All"** (2026-08-17): two buttons at the top of Client
  Access, one graph write each — sets every currently-fillable layer's
  (respecting `horizontal_enabled`) plus the deck's `visible` flag in one
  shot. Deliberately touches only `visible`, never `actions` — blinking the
  whole table off and back on shouldn't also strip a client's already-
  granted flip/deal/draw permissions.
- **Layout/Loose visibility, with a cascade (2026-08-17)**: two more Client
  Access rows, `"_layout"`/`"layout"` and `"_loose"`/`"loose"` pseudo
  entries following the same pattern as the deck's. "Layout" gates whether
  the client sees the table shape *at all* — every `SlotVisual`'s own
  `.visible`, independent of any card's own visibility — starts checked
  (`_layout_visible`, a persistent controller-side flag that survives a
  table reset, unlike the rest of `_acl`) so a session reveals the empty
  layout at Start Reading rather than only once something's dealt into it.
  Unchecking it cascades: every per-slot row *and* Loose go off too
  (`Main._cascade_layout_off()`) — Reading-Model.md's "everything but the
  deck is a child of the Layout," taken literally. "Loose" is an
  all-or-nothing visibility toggle for loose cards as a category (no
  per-card granularity, per the ask) — `grant-api`'s
  `_filter_state_for_client` used to drop `state["loose"]` unconditionally
  for every client; now gated the same way. Fixed a real, previously
  undiagnosed bug in the same pass: `_on_start_pressed()` called
  `send_ws()` immediately after `connect_ws()`, but `connect_to_url()`
  only starts the handshake — `send_ws()` silently no-ops until the socket
  reaches `STATE_OPEN`, so the very first state/acl push (the one
  carrying the layout) was essentially always dropped. Now awaits
  `ApiClient.ws_opened` first.
- **Session lifecycle hardening (2026-08-17)**: two independent fixes,
  found via live "client sees a ghost of the previous reading" testing.
  (1) Client-side: a background loop (`Main._watch_session_identity()`)
  re-asks `/paratarot/sessions/current` every 5s regardless of what the
  WebSocket itself believes its own state is, and forces a full board
  reset the moment the session it's connected to isn't the real current
  one anymore — `ws_closed` was already handling the *clean* disconnect
  case, this is the belt-and-suspenders path for a connection that drops
  without a proper close frame (e.g. a `grant-api` restart, which happens
  on every deploy and wipes all in-memory sessions). (2) Server-side, the
  actual root cause once found: End Reading's "save" message
  (`close_session: true`) only ever wrote the graph checkpoint — the
  session stayed registered as `_current_session_id` until the
  controller's own WebSocket happened to fully disconnect, a second
  network round trip with no guaranteed timing relative to the
  controller's very next Start Reading (which only creates a fresh
  session if none is already "current"). Ending one reading and
  immediately starting the next could both still see the stale session
  and silently reconnect to it — no client-side fix could ever catch
  this, since the client wasn't malfunctioning, it was correctly
  reflecting what the server told it. `close_session` now retires the
  session immediately in the same message handler, not on disconnect.
- **Card info: a hover-updated window near the bottom + right-click "Show
  Detail" (2026-08-22, controller only)**: hovering any dealt card (slotted
  or loose) updates a `ContextWindow` (new file, `Nodes/ContextWindow.gd`)
  defaulted to a spot near the bottom of the table. **Went through two
  reworks the same day** before landing here. First shipped as a
  mouse-following popup with a "Tear away" button inside it — reworked on
  direct feedback that reaching the button meant moving off the card and
  into the popup, precisely the problem that made Paradotz's own
  node-hover panel static in the first place. That rework made it a
  fixed/anchored/non-interactive docked bar — reworked *again*, same day,
  on further feedback: it isn't docked or anchored at all, it's just a
  perfectly ordinary `ContextWindow` instance the user can drag and resize
  like any other. Tear-away lives at right-click → **"Show Detail"** on
  the card's existing context menu (`_show_card_context_menu`/
  `_show_loose_context_menu`) — a deliberate click, not a hover-then-reach
  gesture — spawning an independent copy. **Third same-day refinement**:
  every `ContextWindow` — the hover one and every torn-away copy alike —
  now has both a Paradotz-style roll-up toggle ("v"/">", collapses to just
  the header row, `_toggle_roll()`) and a close ("x") button, plus a new
  **"Ctx" button** in `ControllerPanel`'s top row (mirroring Paradotz's own
  `Ctx` button exactly, including its font-dim/bright on/off styling) that
  toggles the hover window's visibility — except closing the hover window
  via its own (x) is a deliberate "turn this off," not undone by hovering
  again; only pressing **Ctx** rebuilds a fresh one at the default spot
  (`_on_ctx_toggled()`/`_build_hover_context_window()`), same two-case
  logic as Paradotz's `_ctx_toggle()`. Pinned "Show Detail" copies are
  entirely unaffected by Ctx/the hover window either way. Every
  `ContextWindow` is otherwise identical: draggable via its header row,
  resizable via three edge/corner handles (right/bottom/corner, same idea
  as Paradotz's own resize handles) — "context windows that can exist
  simultaneously," one class, not several variants. Written with zero
  tarot-specific dependencies (just `set_content(header, body)`) — the
  intended canonical version to copy into Paradotz (whose own equivalent
  panel is genuinely bespoke, hardcoded into `Editor.gd` as module-level
  singleton state, no class/scene) and Plotz later, same "ported
  technique, not shared code" convention already used between these three
  separate Godot projects — not done this pass, real future work. Card
  content excludes the image (already on-screen as the card itself), and
  never touches the card's image regardless of what Ava calls the property
  (skips any `media_*`-typed schema property, not a hardcoded field list).
  **The real point of this pass**: read card data out of the `tarot-deck`
  graph's own `Card` nodes instead of the static bundled `Data/cards.json`
  (which stays authoritative only for `image`/`godot_scene`/`status` —
  asset/build concerns). A one-off seed script was written
  (`Grant/server/auth-service/seed-tarot-cards.js`, same idempotent pattern
  as `seed-personas.js`) to backfill these from `cards.json` if they were
  ever missing — running it live turned up a genuine surprise: **all 78
  `Card` nodes already existed**, richer than planned (each with a real
  uploaded `portrait` image via Paradotz's gallery-node media feature, real
  x/y canvas positions, `keywords_upright`/`keywords_reversed` as
  already-comma-joined long-text rather than arrays) — evidently built
  directly in Paradotz before this session, unrelated to any code path
  ava_tarot itself reads. The seed script's own idempotency check (match by
  `card_id`) correctly no-op'd against every one of them; nothing was
  overwritten. Paratarot's own reading code was written against the
  *schema*, not that assumption, so this cost nothing to discover: exactly
  the Trait pattern already established in this file
  (`_parse_traits()`/`_ensure_trait_note_schema()`) applied to a second
  node type — `_parse_card_props()` reads `Card`-typed nodes out of `_graph`
  generically, and the hover/tear-away content builder
  (`_build_card_hover_content()`) walks the graph's own
  `type_schemas["Card"].properties` in order, explicitly skipping any
  `media_*`-typed property (the real schema's `portrait` field, in
  particular) rather than a hardcoded field list — so Ava adding a wholly
  new Card property (a real prose "meaning" field, say) directly in
  Paradotz shows up here with zero Paratarot code change. Deliberately
  read-only for now — no in-app editing UI; Paradotz is the edit surface,
  per explicit direction. (Cosmetic, left alone rather than touched:
  the live schema's `card_id` property is itself `show_in_hover: true`,
  so it appears as its own line under the card's name — harmless, just
  slightly redundant; easy for Ava to flip off in Paradotz if it bothers
  her.)
  New `CardNode` signal `hover_entered` (none existed before — only
  tap/right-click did), relayed up through `SlotVisual` → `CardWorld` →
  `Main.gd` on the same pattern `tapped`/`context_requested` already use.
  No `hover_exited` handling anywhere — the hover window deliberately keeps
  showing the last-hovered card's info rather than reverting to a
  placeholder the moment the mouse moves off it, which is what "static and
  less intrusive" actually meant in practice; this also made the original
  version's grace-period hide-timer hack unnecessary, not just its
  "Tear away" button. **Two follow-up fixes/additions, same day:** (1) the
  header row's `MarginContainer` was missing `size_flags_horizontal =
  EXPAND_FILL` — its parent is a Container, which ignores a child's own
  anchor presets entirely, so it shrank to minimum size and sat at the
  header's left edge, dragging the roll/close buttons in next to the title
  instead of pinned to the window's right edge (this is why they read as
  "on the left"). (2) **The hover window's position/size/rolled state now
  saves with the Layout**, per explicit ask — a `ctx_window` property on
  the Layout graph node itself (`{"x","y","width","height","rolled"}`,
  `ContextWindow.get_geometry()`/`set_rolled()`), written into the same
  batch `_on_slots_saved()` already commits on "Save Layout" (not a new
  auto-save trigger — matches this repo's own established "preview live,
  persist only on explicit Save Layout" convention exactly), and restored
  in `_apply_active_layout()` on load/switch. A layout that's never saved
  one just leaves the window wherever it currently is, rather than
  snapping to a default.
- **Planet/Element concept nodes (2026-08-22, controller only)**: two new
  graph node types, `Planet` and `Element`, seeded once via
  `Grant/server/auth-service/seed-tarot-concepts.js` (one node per distinct
  value already present across the 78 `Card` nodes' own `element`/`planet`
  properties — not a hardcoded textbook list) with a minimal `description`
  (`text_long`) schema so Ava can attach real content to them in Paradotz
  over time, same "enrich via Paradotz" pattern as `Card` itself. On the
  table, a small non-card `ConceptNode` (new file, `Nodes/ConceptNode.gd`)
  appears — connected by a line, "same feel" as the MODIFIES mechanic —
  for every Planet/Element any currently dealt or loose card references,
  and disappears once none do; draggable the same press-then-track way
  loose cards are (`CardWorld._on_concept_drag_pressed`/
  `_input_concept_drag`), position remembered for the session
  (`_concept_positions`, not persisted to the graph — these are transient
  table aids tied to what's in play, not permanent furniture like Slots).
  **Deliberately no new property type or graph edge for the Card↔concept
  link itself** — considered and rejected both `graph_query` (built
  earlier this session; wrong tool, that's for a *different* graph over
  the network) and `list_node` (Paradotz's existing same-graph reference
  type — confirmed it stores/display the referenced node's name directly
  with zero id-resolution, but Paradotz has **no reverse-lookup mechanism
  anywhere**, and this feature's actual need is the reverse direction:
  "given a Planet, which in-play cards reference it," not the forward
  one). Computed entirely client-side instead: `CardWorld.set_card_lookup()`
  hands it `Main._deck` (already fully populated with every card's
  `element`/`planet` at all times, confirmed no extra graph read needed)
  once; `_refresh_concept_nodes()`, called at the end of both
  `apply_state()` and `set_loose()`, covers every one of `Main.gd`'s ~15
  scattered state-mutation call sites for free, since they all funnel
  through those two functions before anything renders — no new hook
  needed anywhere in `Main.gd` itself. Card's own `element`/`planet` text
  properties are completely untouched by this feature.
- **Session Theme (2026-08-22)**: a free-text field in the Session
  rollup's in-session group, right above Payment — every reading has some
  question/feeling driving it, whatever it actually is, worth recording
  alongside the payment info. Exact same pattern as Payment in every
  respect: explicit "Save Theme" button rather than live-per-keystroke
  (a half-typed theme shouldn't get written either), resets blank at the
  start of each new session (`set_in_session(true)`), a new `"theme"` WS
  message writing straight onto the Session graph node server-side
  (`grant-api`'s handler, direct-property-write, never part of
  `state`/`acl`, never broadcast to a client) — `theme: ""` seeded
  alongside `payment_*` at Session-node creation for the same consistency
  reason. Grant-side-only change, no Paratarot deploy needed for the
  server half but both are shipped together here anyway.
- **Querent rollup — client notes (2026-08-22)**: a new rollup, separate
  from Traits by deliberate design ("overlap," not merge — confirmed with
  the owner directly: Traits stays a shared, reusable vocabulary; this is
  free-text notes specific to one client). Same focus rule as Traits
  (in-session locked to `_pending_client`; out of session, its own
  independent picker — `_querent_client_menu`/
  `get_querent_selected_client()`, deliberately not shared with Traits' or
  Session's own pickers, same reasoning `_build_traits_section()`'s doc
  comment already gives for keeping those two apart). Unlike Session
  Theme/Payment, **this is client-persistent, not session-scoped** — it
  reads/writes the focused client's own `notes` property on their actual
  `Client` graph node (not the Session node), so switching focus loads
  whatever's already saved there rather than starting blank
  (`_focused_client_notes()`, straight off `_graph`). New `"querent_note"`
  WS message (`grant-api`) creates the Client node first if it doesn't
  exist yet (same id scheme `_ensure_client_node` already uses, so a
  client picked out-of-session with no prior reading doesn't end up with
  a duplicate node once a real session eventually happens with them).

### What is not yet done (deliberately deferred, not forgotten)
- Background (Step 6's other half) — per-Layout fill-color/image, not started
- Celtic Cross / Ava's Celtic Cross layouts (buildable now via the Layout
  editor, just not pre-seeded)
- `point` ACL action — never wired up client-side (protocol has room for
  it, nothing uses it). `pick` itself is done as of 2026-08-17 — see "What
  works" above (Can Draw & Select / Can Select Loose, click-to-carry drag,
  full place/free/modify resolution) — this bullet used to lump the two
  together and call both open; only `point` still is.
- In-app editing of Card content (currently Paradotz-only, deliberately —
  see 2026-08-22 above); reading history browser
- Stats-model nodes as their own queryable type (reading metrics currently
  just live as empty properties on the Scenario node) — see the
  2026-08-17 "future direction" note below, this is about to become a
  real near-term priority, not just a someday item
- Kuzu-as-primary-store migration on the Grant side (separate, near-term
  session — see `Grant/docz/infrastructure/data-architecture.md`) — until
  then, cross-reading trend queries over many Scenario nodes are JSONB-blob
  full-loads, fine at current scale, not built yet anyway

**Future direction, stated 2026-08-17, not yet scoped or started:** more
Scenario-recording work is coming; the owner wants to start attaching
*weights* to data-model items (which cards, which traits, which placements
matter how much), feeding into a stats layer that would ultimately drive
the color palette of a slot's own glow/halo and the table background
itself — the visual language reacting to the reading's own content, not
just structural on/off state the way it does today. Also wants
client-centric worksheets that eventually become real documents and
reporting-dashboard items. Explicitly lower priority than the site-launch
work below for now — see Grant's own CLAUDE.md "Last Session" for the
current overall priority order across both repos.

---

## Non-obvious bugs worth knowing before touching drag/drop code

The 2026-08-16 drag-and-drop work went through several real, distinct bugs
before landing — recorded here because a couple of them are the kind of
thing that's easy to reintroduce by "obvious" refactors:

1. **`CardNode.visible` cannot mean two things at once.** The root cause of
   the session's hardest bug: `CardWorld._resolve_loose_drop()` used
   `CardNode.visible` to mean "this layer genuinely holds a dealt card,"
   but the drag-hover preview (`_set_drag_hover()`'s "place" branch) *also*
   sets `.visible = true` on an empty layer purely to render its green
   outline. Hovering an empty Vertical → correctly resolves to "place
   Vertical" → the preview sets `visible = true` to draw the hint → the
   very next motion frame's resolve call reads that same flag and now
   believes Vertical is filled → flips to offering Horizontal → clearing
   the stale Vertical hint sets it back to `false` → flips back to Vertical.
   A continuous, self-inflicted oscillation, entirely from one flag serving
   two callers with different meanings. Fixed by adding `CardNode.has_data`
   — set only by `SlotVisual.set_layer()` from real state data, never
   touched by hover/highlight code. Any future "is this layer filled" check
   must use `has_data`, never `visible`.
2. **A layer's crossing rotation must be set at creation, not first use.**
   `SlotVisual._build_card_layer()` used to set `node.layer = layer` as a
   raw property assignment, which skips `CardNode.set_layer()`'s call to
   `_update_rotation()`. A Horizontal layer that had never been dealt into
   sat at rotation 0 (the Control default) instead of 90° until the first
   real deal called `set_orientation()` (which also updates rotation) —
   until then both its hit-test rect and its drop-hint outline were in the
   wrong, unrotated place. Always construct a layer via `set_layer()`,
   never a raw `.layer =` assignment.
3. **A fixed coarse gate can't both cover Horizontal's real footprint and
   avoid a close neighbor's.** Two attempts at gating `_resolve_loose_drop()`
   with a per-slot bounding rect both failed on a real (if tightly-spaced)
   layout: Horizontal's actual rotated footprint is 280px wide, wider than
   the 180px `CardNode.slot_collision_rect()` (sized off Vertical alone)
   guarantees between two slots when *dragging* one — so two "legally"
   spaced slots can still have overlapping Horizontal hit zones. The fix
   that actually held: don't gate at all — collect every slot the point
   precisely hits as a candidate, then pick whichever candidate's own pivot
   is physically closest to the point ("nearest slot wins").
4. **Reversal (180°) flips both axes around the pivot, not just one.** Any
   anchor-point math for a card (the loose label's position, the modify-
   link endpoints) that needs to stay put on the table regardless of
   `orientation == "reversed"` must inverse-transform a *fixed, upright*
   target point through the card's actual rotation — not hand-derive a
   separate "reversed" offset by eyeballing one axis, which is exactly the
   mistake that shipped once and sent the loose label sideways instead of
   staying below the card. `CardNode.get_layer_transform()` (drops rotation
   to just the structural `layer_angle()`, ignoring `reversed_angle()`) is
   the vetted pattern for "where does this sit ignoring reversal."
5. **When a live screenshot contradicts your read of the code, add a debug
   overlay before guessing again.** Several rounds of this investigation
   were spent misreading rotated phone photos of the screen (aspect ratio
   and relative position are both genuinely hard to judge from a photo
   taken at an arbitrary angle). A temporary on-screen text readout
   (`CardWorld._debug_resolution_text`, removed once bug #1 above was
   found) that printed the actual resolved slot/layer/flags settled every
   remaining ambiguity in one screenshot instead of several more rounds of
   guessing from shape.

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
│   ├── CardNode.gd             ← single card layer: face up/down _draw(), tap-to-act; loose
│   │                              layers additionally draggable + get their own name label
│   ├── SlotVisual.gd           ← one Slot's Vertical+Horizontal CardNodes + name/sub-labels +
│   │                              glow/halo as one cohesive node, real graph-backed positions
│   ├── DeckVisual.gd           ← the physical deck object (2026-08-16) — draggable stack,
│   │                              hover/hold-to-draw gesture, right-click menu
│   └── CardWorld.gd            ← the card table; pan/zoom container technique ported from
│                                  Paradotz's Editor.gd (not wired to input yet — not needed
│                                  for one fixed 3-slot layout that fits on screen). Owns all
│                                  drag/drop resolution (loose-card place/modify, edge-drag
│                                  Modify Card, slot-marker dragging, the deck marker's own drag)
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
├── Assets/Images/             ← 78 card PNGs + card_back_default.png (drawn on the table and
│                                  the deck marker; falls back to a name-text/color placeholder
│                                  for any card whose art isn't resolved)
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
| Code-first UI, no hand-authored complex scenes | `ControllerPanel`/`ClientOverlay`/`CardWorld`/`CardNode`/`SlotVisual`/`DeckVisual` are all `class_name` scripts instantiated via `.new()`, not `.tscn` hierarchies — only `Scenes/Main.tscn` is a real scene file, kept to a single root node |
| Paradotz's web-export conventions carried over | GL Compatibility renderer, `canvas_items` stretch, MenuButton-only (not OptionButton), Latin-1/ASCII-only button text — all hard-won lessons from Paradotz's HTML5 export, not rediscovered here |

---

## Realtime Protocol (grant-api's `/ws/paratarot/{session_id}`)

Controller → server: `{"type": "state", "payload": {"cards": {slot_id: {vertical, horizontal}}, "loose": {...}, "slots": {slot_id: {name, x, y, scale, horizontal_enabled}}}}`, `{"type": "acl", "payload": {...}}`, `{"type": "save", "payload": {"client", "scenario", "placements", "close_session"}}` (checkpoint — `close_session: true` is End Reading, `false` is a mid-session Record).

ACL shape is `{slot_id: {layer: {"visible": bool, "actions": [...]}}}` for real Slot/Vertical/Horizontal layers, plus three pseudo slot_id/layer pairs that reuse the exact same shape for things that aren't real Slots: `"_deck"`/`"deck"` (`actions` any of `deal_next`/`draw_loose`/`draw_select`/`select_loose`/`place_slot`/`place_free`/`modify`/`loose_fallback` — see ava_tarot's own "Deck client access" in "What works" for what each means), `"_layout"`/`"layout"` (`visible` only — gates every `SlotVisual`'s existence on the client's screen, independent of any card's own visibility), `"_loose"`/`"loose"` (`visible` only — all-or-nothing for loose cards as a category, no per-card granularity).

Server → client: `{"type": "state", "payload": {"cards": {...filtered by ACL...}, "slots": {...unfiltered, structural...}, "loose": {...all-or-nothing by "_loose" ACL...}}, "acl": {...unfiltered — a client needs to know what it's granted, not just what it can currently see...}}`.

Client → server: `{"type": "action", "card_id", "layer", "action", ...extra}` — server validates `action` against `acl[card_id][layer].actions` before forwarding (whole message, not just the four core fields — the loose-card resolution actions carry extra targeting fields: `loose_id` always, plus `slot_id`/`target_layer` for `place_slot`, `target_card_id`/`x`/`y` for `modify`, `x`/`y` for `place_free`); controller decides how to apply it and rebroadcasts. `select_loose` never reaches the server at all — picking up an already-loose card is pure client-side UI, only the eventual drop needs the controller.

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
had been live and un-fixed since Paratarot shipped. `v0.22.0` as of the
2026-08-17 session (started that session at `v0.16.2`, ended the 2026-08-16
session there) — every fix in this file's "Non-obvious bugs" section landed
as its own version bump, deployed and hands-on re-tested individually
rather than batched, which is how a diagnostic-overlay screenshot could be
tied to an exact build. The client view now shows its own version number
too (top-right corner, added 2026-08-17) — it has no ControllerPanel to put
one in, but the same "only way to confirm a deploy reached this build"
reasoning applies, and it's genuinely how the client-never-rendered-cards
bug that session (see "Current State" above) got confirmed fixed.

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
5. ~~**Card dragging + loose cards + the modifier mechanic**~~ — done
   2026-08-16, both paths. Piece 1 (2026-08-13): Deal Loose + "Modify Card"
   as a right-click path — reworked 2026-08-16 into an edge drag (grab the
   loose end, hover any card for the amber highlight, click/right-click/
   Escape to resolve or cancel) rather than a text list that named
   candidates by name even face-down. Piece 2, the three-way drag
   resolution (empty→Vertical / filled-Vertical→Horizontal / occupied→
   `MODIFIES`), landed 2026-08-16 with a live amber/green hover preview and
   went through several real bugs before it was solid — see "Non-obvious
   bugs" above, especially the `visible`-vs-`has_data` feedback loop.
   Per live feedback, Horizontal's own footprint takes priority to fill it
   once Vertical is occupied (not the reverse), and each slot also has its
   own "Horizontal on" checkbox in the Layout editor (off = a filled
   Vertical reads as the whole slot being full). Also added, same day: a
   draggable deck object with its own hover/hold-to-draw gesture (see "What
   works" above) — not originally in this roadmap, but built on the same
   loose-card drag machinery this step produced.
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
- Deck client access, Piece B — done 2026-08-17, see "What works" above.
  `point` ACL action and `pick` as an actual client-controlled drag gesture
  (vs. today's server-authoritative one-tap Deal Next/Draw Loose) still open.
- Reading history browser reading from the graph's Scenario nodes instead of a flat file
