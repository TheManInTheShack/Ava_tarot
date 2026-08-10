---
type: meta
title: Reading & Scenario Data Model
---

# Reading & Scenario Data Model

This document defines the conceptual architecture for readings, layouts, sessions,
and clients in the Ava Tarot knowledge graph. It is a design reference, agreed
2026-08-10 — nothing described here is implemented yet beyond the base 78-card
catalog and a simpler, superseded checkpoint write (`Scenario` node + flat
`PLACED` edges straight to `Card`, no `Layout`/`Slot`/`Session` nodes). This
revision replaces the 2026-04 draft of this document, which sketched similar
territory (Layout/Slot promotion, positional scenarios) but was never wired up
and left an unresolved gap between its own property-based and edge-based
scenario designs. That gap is resolved here.

---

## Guiding principle

There is no separate configuration surface. Layouts, slots, backgrounds,
traits, sessions, clients, scenarios — all of it is the same evolving graph
the 78 cards live in. "Editing a layout" is a graph write, not a JSON file
edit. This is a direct extension of the platform-wide rule that the graph is
the canonical source (see Grant's own `CLAUDE.md`), applied all the way down
to what used to look like static config (`Data/layouts.json`, now dead and to
be retired once this is built).

---

## Node types

| Type | Status | Description |
|------|--------|-------------|
| `Card` | Live | One node per card (78 total) — the starting material, unchanged |
| `Client` | Live, renamed | Was "Customer"; a real logged-in `public`-role account. Consulting-business framing, not a game. |
| `Layout` | Design only | One node per named spread (e.g. "Classic Simple") |
| `Slot` | Design only | One node per position within a Layout, edged to it |
| `Vertical` / `Horizontal` | Design only | The two layers of a Slot — see below |
| `Background` | Design only | A small managed list, same shape as `Trait`/`Tag` |
| `Trait` | Design only | A small managed list, same shape as `Tag` — personality tags on a Client |
| `Session` | Design only | A formal, numbered entity — see below |
| `Scenario` | Live, extended | One per recorded reading; gains a direct Client edge and can recur within one Session |

---

## Structural vs. instance data — the property-placement rule

Two different kinds of fact live in this graph, and they go on different kinds
of thing:

- **Structural** — true about the *design* of a layout, persists across every
  reading that ever uses it: a Slot's position, a Layer's rotation, a Layer's
  labeling strategy, a Layout's chosen Background. Lives on the
  `Layout`/`Slot`/`Vertical`/`Horizontal`/`Background` nodes themselves.
- **Instance** — true about *one specific placement event*: which card, which
  orientation, which session/scenario/client it happened in. Lives on the
  **edge** connecting a `Card` to whatever it was placed on, created fresh at
  deal time, never on the structural nodes.

This is why inversion status (upright/reversed) is an edge property, not a
Layer property, even though both "belong" to the same slot conceptually.

---

## Layout → Slot → Layer hierarchy

```
Layout ("Classic Simple")
  └─HAS_SLOT→ Slot ("Past")
                └─HAS_LAYER→ Vertical   (the primary card position, 0°)
                └─HAS_LAYER→ Horizontal (the crossing/modifier position, 90°)
```

Node names are composite to stay globally unique across every layout without
a separate compound key: `classic-simple-past-vertical`,
`classic-simple-past-horizontal`, etc.

Each Slot uniformly has **exactly two layers**, no more — Vertical (the
initial card) and Horizontal (its modifier), which physically cross, matching
the classic crossing-card visual (and the 2026-04 draft's already-invented
`placed_upright`/`crosses_upright` vocabulary — "crossing" was always the
horizontal orientation, just never promoted to a real node before now).

Slots themselves are ordinary graph entities: instantiable, movable,
deletable, and "frozen" into a named Layout by simply being edged to it — no
separate freeze/save step beyond the normal graph write.

**Layers are controlled independently** — visibility/actions ACL is
per-layer, not per-slot (today's ACL is slot-granularity only; this is a
real widening, not just a UI relabel — a slot's Vertical card can be visible
while its Horizontal modifier stays hidden, or vice versa). The one
placement constraint: **a slot's Vertical layer must be filled before its
Horizontal layer can be** — you can't place a crossing card over an empty
position.

**Slots carry a deal-order sequence** — a structural property set when the
layout is designed, so "Deal Next" (see Deck section below) has a
well-defined next position rather than an arbitrary one.

---

## Placement edges

Two cases, one edge type (`PLACED`), differentiated by target and a property
— not a proliferating type per placement kind:

**Slotted** — `Card --PLACED--> Vertical` or `Card --PLACED--> Horizontal`
(Vertical must already be filled before Horizontal can be).
Properties: `orientation` ("upright"/"reversed"), `session_id`, `scenario_id`,
`client_id`.

**Loose** — a card dealt onto the table but not occupying any Slot/Layer.
`Card --PLACED--> Scenario` directly, skipping Layer entirely. Properties:
`placement: "loose"`, `session_id`, `scenario_id`, `client_id`. Loose-and-
never-attached is a legitimate, permanent end state — not a thing requiring
later resolution.

---

## The modifier mechanic (decoupled/attached cards)

Any card, loose or not, can be data-linked to modify any other card already
on the table — not bounded by slot geometry, drawn beside its target with a
connecting line rather than occupying slot bounds.

Edge: `Card(loose) --MODIFIES--> Card(target)`, properties `{session_id,
scenario_id, client_id}` — same identifying items as any scenario-based edge,
so the modification is fully traceable from any of the three anchors.

**Interaction**, ported technique (not code) from Paradotz's loose-node
resolution (`Editor.gd:_resolve_loose_end`): unlike Paradotz's `_loose`
placeholder (which stands in for a node whose *type* is still unknown),
Paratarot's loose card is already a fully-known `Card` — only its *placement*
is undetermined. Two paths resolve it, not one:

1. **Right-click menu** — controller right-clicks the loose card → "Modify
   Card" → picks a target → edge created. Works regardless of position.
2. **Drag-and-drop**, closer to Paradotz's own drag-until-rects-intersect
   technique, and the primary path in practice — the same drag gesture
   resolves to one of three outcomes depending on what's already at the drop
   target:
   - Dropped over an **empty slot** → fills that slot's Vertical layer
   - Dropped over a slot with **Vertical filled, Horizontal empty** → fills
     the Horizontal layer (still subject to the vertical-before-horizontal
     rule above, trivially satisfied here since Vertical is already filled)
   - Dropped over a slot where **both layers are filled** → dragging over
     the visible portion of either of the two occupied cards highlights that
     card; releasing there creates a `MODIFIES` edge to whichever card was
     highlighted, instead of a `PLACED` edge — the drag never fails, it just
     picks a different outcome based on what it's hovering

**Right-click context menu** (per card, ported UI pattern from Paradotz's
`Editor.gd:_show_node_context_menu` — a hand-built overlay + `PanelContainer`
+ flat `Button`s, not a native `PopupMenu`, triggered by
`GraphNode.gd`-style `MOUSE_BUTTON_RIGHT` → `context_requested`):
- **Show/Hide** — relocates the existing per-card ACL visibility toggle (today only a checkbox in the Client Access rollup) onto the card itself
- **Turn** — the existing flip/face-up mechanic, relocated onto the menu
- **Invert** — toggle upright/reversed; genuinely new interactivity, today orientation is only randomized at deal, never toggled
- **Modify Card** — loose cards only; starts the attach-to-target flow above

**Known prerequisite:** cards cannot be dragged at all today (`CardNode`'s own
header comment says so explicitly; it's on `CLAUDE.md`'s deferred list).
"Deal a loose card, then position it" needs dragging built first.

---

## Session

A formal, numbered entity — not ephemeral in-memory state like today's
`_paratarot_sessions` dict, which vanishes on process restart or session end.

```json
{
  "type": "Session",
  "name": "Session 14",
  "properties": {
    "session_number": 14,
    "instantiated_at": "2026-08-10T14:02:00Z",
    "client_joined_at": null,
    "ended_at": null
  }
}
```

- `session_number`, `instantiated_at`, `client_joined_at`, `ended_at` are all
  **fixed properties** (Paradotz's existing fixed-property mechanism,
  `GameState.SHAPE_FIXED_PROPERTIES` — needs adapting from shape-keyed to
  type-keyed, not new invention).
- Numbering is a single global sequential counter — `1, 2, 3...` — not
  per-client, since every session is already tied directly to its Client.
- **The controller declares the client at instantiation** — "this session
  with this customer starts now" — so `Session --FOR_CLIENT--> Client` is
  written atomically at creation, no write-then-patch.
- `client_joined_at` is filled in separately, whenever that client's socket
  actually connects — may stay empty indefinitely. **Interrupted sessions
  stay open passively until the controller explicitly ends them.**
- The controller UI therefore has a top-level mode, **IN_SESSION** or
  **OUT_OF_SESSION**, gating which controls are available (detail deferred to
  the control-surface design pass).

### Layout selection & session state

Choosing a Layout is state-independent, but what it *does* depends on
IN_SESSION vs. OUT_OF_SESSION:

- **Out of session** — changing the selection is passive: it becomes "the
  current selection," nothing else happens. It's simply what a new Session
  would start with by default.
- **In session** — changing it is tantamount to starting over: the deck
  reshuffles back to its ready state and the new, empty Layout appears on
  screen. This does **not** end the Session — same `session_number`, same
  Client, `ended_at` stays null.
- **If cards were already placed** when a mid-session Layout change happens,
  the current table state gets recorded first, same as any other mid-session
  save (above) — a Layout switch is just another trigger for that mechanic,
  not a new one.

### Session ↔ Scenario — one-to-many, not one-to-one

A Session can produce **zero or more** Scenario writes before it closes:

- **Mid-session saves** — "record it and start over in the same session" —
  write a Scenario, do not touch the Session or its `ended_at`.
- **End Session** — diff the live table state against the last-saved
  Scenario (n-1). Only write one more (final) Scenario if something changed
  since that save — no redundant duplicate write — then stamp `ended_at`.

### The Session ↔ Client ↔ Scenario triangle

```
Session --FOR_CLIENT--> Client
Session --HAS_SCENARIO--> Scenario   (one edge per recorded reading)
Scenario --FOR_CLIENT--> Client       (completes the triangle)
```

`HAS_SCENARIO` is a proposed verb, not yet cross-checked against
`Edge-Types.md`'s conventions — flag for confirmation when this is built.
`FOR_CLIENT` already exists live (today's `Scenario --FOR_CLIENT--> Client`
checkpoint edge); reused here rather than inventing a second verb for the
same relationship.

Any of the three nodes can be the query entry point: from a Card's placement
edges you reach its `session_id`/`scenario_id`/`client_id` directly without
walking the triangle at all — "approach it from any point."

---

## Background

Not Paradotz's freeform decoration system — meant to feel like a tabletop
surface, not an editable canvas.

- **Node type**, same shape as `Trait`/`Tag`: `name`, `fill_color` (v1 — a
  muted/desaturated swatch picker, not Paradotz's full 40-color strain
  palette), later `image` (a `media_image` property, same mechanism Card
  portraits already use) plus a tile/stretch mode (genuinely new — Paradotz's
  Gallery fit-modes today are Fit Frame / Fit Picture / Adjust Frame only, no
  tiling exists yet).
- **Scoped per-Layout**, not global — "any layout is just a set of positions
  of other elements," so the background is recorded alongside a Layout's
  slots and positions: `Layout --USES_BACKGROUND--> Background`.
- Managed from the state-independent tier of controller UI (see Traits,
  below) — picking a background doesn't depend on being in or out of a
  session.

---

## Traits

Personality tags on a Client — emotional states, personality tropes, later
possibly structured properties like Myers-Briggs type. **Exactly Paradotz's
Tag/HAS_TAG mechanism**, not a new system:

- `Trait` node type, locked against rename/delete through the regular Node
  Types UI the same way `type_name == "Tag"` is special-cased today in
  `GraphPanel._start_type_edit()`.
- `Client --HAS_TRAIT--> Trait` edges.
- A "Trait manager" in the controller UI is a shortcut into this same
  operation — not a separate rules engine.
- Available from the **state-independent** tier of controller UI (same tier
  as Background) — traits get reviewed/added regardless of session state.
- Additional Client properties (MBTI type, etc.) are ordinary optional
  properties on the `Client` type schema, same weight as `Card`'s
  `element`/`planet`/`zodiac` — not fixed/undeletable, since they're
  discretionary data Ava fills in as she learns it, not structurally
  load-bearing like Session's timestamps.

---

## Client identity: username vs. display name

Not a graph concept by itself, but denormalizes into the `Client` node's
`name` property, so worth recording here.

- `users.username` stays exactly as constrained today (`^[a-z0-9_]+$`,
  unique, the login handle) — unchanged.
- New `users.display_name` column (nullable free text) — shown wherever a
  human should see "who this is": dashboard "Signed in as", admin Users
  list, and the `Client` graph node's `name` (today literally
  `client.get("username", "")` at checkpoint time — becomes `display_name`
  with fallback to `username` so nothing ever renders blank).
- Standard handle-vs-display-name split (Slack/Discord/GitHub precedent),
  not something novel to invent.
- Six test personas planned (Beatles-derived): Eleanor Rigby, Billy Shears,
  Pamela Polythene, Martha Mydear, Rocky Raccoon, Michelle Mybelle — ordinary
  `public`-role Client accounts through the existing invite flow, once
  `display_name` exists. Real client registration (an authored opening/index
  page) is still unbuilt; only the test-client login exists today.
- Open question, not yet decided: does the client self-edit their own
  `display_name` later (parallel to existing self-serve password/recovery-
  email), or admin-set-at-invite only? Either covers the immediate persona
  need.

---

## Deck state & dealing

Dealing is **state-independent** — out-of-session play is meant to feel
freeform: a layout can be built and cards thrown down with nobody in a
session at all. The difference is purely about persistence, not
capability: out-of-session dealing produces **no scenario data**, which
falls straight out of the placement-edge schema above rather than needing
special-casing — `PLACED`/`MODIFIES` edges always carry
`session_id`/`scenario_id`/`client_id`, none of which exist outside a
session, so there's simply nothing to write.

Reshuffle/Unshuffle imply the deck has a **persistent standing order**, not
the fresh `ids.shuffle()` done inline at deal time today
(`_on_deal_pressed()` currently shuffles and deals all three fixed slots in
one shot). Dealing becomes "draw from the top of a standing order," one card
at a time. That order is ephemeral, live WS-session state — same tier as
today's `_state` — not a graph concept; nothing about deck order gets
persisted.

Six actions:

- **Reset** — clear the table back to empty
- **Reshuffle** — randomize the standing order
- **Unshuffle** — restore canonical/catalog order (Major Arcana 0–21, then
  suits Ace–King) — a presentation move, showing the deck in recognizable
  order before shuffling for effect
- **Deal to Slot** — targeted placement into a specific slot/layer
- **Deal Next** — draw the top card into whichever slot is next per the
  layout's deal-order sequence (see Slot properties, above)
- **Deal Loose** — draw the top card as an untethered card (feeds into the
  drag-drop resolution logic under Placement edges, above)

---

## Controller panel structure

Rollup sections, same visual pattern as today's `ControllerPanel`, but
data-driven off the real Slot list instead of hardcoded, and split across
three tiers:

**Out-of-session only**
- **Session** — client picker (closed list of registered `public`-role
  Clients) + "Start Session"

**In-session only**
- **Client Access** — one row *per layer* (Vertical + Horizontal
  separately), generated from the active Layout's real Slot list, replacing
  today's hardcoded `["1","2","3"]`
- **Session** (same section, different controls once in-session) —
  "Record Scenario" (mid-session save) and "End Session" (diff-check against
  the last save, then close)

**State-independent**
- **Layout** — select the active Layout, and edit it (instantiate/move/
  delete/freeze Slots); changing the selection out of session is passive
  (just becomes the default for the next session), in-session it's a
  mid-session restart (deck resets, new empty Layout appears, any existing
  placement gets saved first, same as any other mid-session save)
  - **Background** nested inside Layout's section rather than a separate
    top-level rollup, since it's structurally a per-Layout property
    (`Layout --USES_BACKGROUND-->`)
- **Traits** — manage the Trait vocabulary and assign to whichever Client is
  currently in focus (the client picked for the next session, or the active
  session's client)
- **Deck** — the six dealing actions above

---

## Still open / not covered by this revision

- The panel structure above is agreed at the tier/section level; the actual
  widget-level UI (exact controls, layout within each rollup) isn't designed
  yet.
- New edge types named in this document (`HAS_SLOT`, `HAS_LAYER`,
  `USES_BACKGROUND`, `HAS_TRAIT`, `MODIFIES`, `HAS_SCENARIO`) still need to be
  formally added to `Edge-Types.md`'s taxonomy, same as the 2026-04 draft
  promised for its own new types and never did (`PLACED`/`FOR_CLIENT` are
  *live* today and still undocumented there — a pre-existing gap, not
  introduced by this revision).
- Card dragging is a hard prerequisite for the loose-card/modifier UI.
- Backend implication carried over from the 2026-04 draft, still true:
  `grant-api`'s checkpoint writer (`_apply_paratarot_checkpoint`) needs real
  rework to write Layout/Slot/Layer/Session nodes and the new edge shapes —
  not just a client-side data model change.

---

## Aggregate scenarios & phase space (untouched by this revision, still future work)

Everything below is unchanged from the 2026-04 draft — no part of this
session's design conversation touched it. Kept for continuity; still
speculative, still Phase 3+.

### Aggregate scenarios (pattern-wide, not slot-bound)

Not tied to a slot — describe a property of the entire spread:

| Dimension | Description | Representation |
|-----------|-------------|-----------------|
| **Major Arcana density** | Ratio of major arcana cards to total | `n_major / n_total` → scalar (0.0–1.0) |
| **Suit distribution** | Relative presence of each suit | `[Wands, Cups, Swords, Pentacles]` → 4-vector |
| **Value distribution** | Relative presence of each pip value | `[Ace, 2–10, Page, Knight, Queen, King]` → 14-vector (or 4-group: low/mid/high/court) |

Additional optional dimensions: inversion ratio, court density, suit entropy
— each a computed metric, derived automatically at save time, not admin-defined.

### Phase space & reading fingerprints

A reading maps to a point in a multi-dimensional feature space; readings that
share a "feel" cluster near each other.

**Compact feature vector:**
```
[major_ratio, wands_frac, cups_frac, swords_frac, pents_frac, inversion_ratio, court_ratio, value_entropy]
```

**Color metaphor:** Hue = elemental balance (Fire=0°, Water=90°, Air=180°,
Earth=270°, angle through the four suits); Saturation = major arcana density;
Value = intensity (inversion ratio + value entropy). Gives each reading a
single HSV fingerprint — a legitimate dimensionality reduction, not just a
metaphor, but uncalibrated against real data yet.

### Scenario instantiation workflow (still applies, now sits alongside Session)

1. A reading is completed and saved (Scenario write, as above).
2. The admin reviews and optionally flags subgraph patterns as named
   aggregate scenarios.
3. A scenario instance is created, linked to the reading, tagged with notes.
4. Recurs across readings; instance list grows.
5. Admin can query: "every time The Moon crossed The Hanged Man, what was the
   outcome?" — now directly answerable via `MODIFIES`/`PLACED` edge
   properties rather than requiring a bespoke scenario record for every case.
