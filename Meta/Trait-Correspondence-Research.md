# Trait–Card Correspondence: Prior Art Research

Research pass, 2026-08-18, prompted by a real question: our Traits (seeded
from an OCEAN/Big Five weighting system — `Trait--LOADS_ON-->OceanFactor`,
see `Grant/server/auth-service/seed-personas.js`) are one vocabulary. Tarot
cards carry their own traditional keywords/meanings. If a card's keywords
*were* trait vocabulary — same graph, same edges — has this been done
before, formally? Answer: not quite, and the gap is informative.

---

## What exists

**One real empirical study, and it's a negative result.** Dimas Armand,
*"The Validity of Tarot as a Personality Inventory"* (ANIMA Indonesian
Psychological Journal). 494 psychology students, each assigned a Major
Arcana **birth card** (a real tarot subtradition — one card per birthdate),
compared against their actual Big Five scores via the IPIP inventory.
ANOVA and cross-tabbing found no significant differences between Big Five
aspect scores across birth-card groups. Conclusion: tarot doesn't hold up
as an alternative Big Five inventory, at least not via birth-card
assignment.

**Important scope note:** this tested a *different* question than the one
we're asking. It's whole-card birth-assignment against broad Big Five
*scores* — a person gets one card, does that predict their personality
survey results. Not keyword-level semantic mapping against trait *facets*
— a card's meaning-text analyzed for which specific traits it evokes. The
negative result is worth knowing (don't expect "your birth card explains
your Big Five profile" to hold up), but it doesn't actually test our idea.

**Well-documented, but not Big Five:** the 16 tarot court cards correspond
one-to-one with the 16 Myers-Briggs (MBTI) types — this comes up
constantly across both tarot and MBTI communities, informally but
consistently. MBTI itself is the weaker, less psychometrically-validated
framework next to Big Five/OCEAN, so this is a real, load-bearing cultural
correspondence, just not the rigorous one.

**Extensive, but archetypal not psychometric:** the Major Arcana's modern
esoteric interpretation (Golden Dawn, Waite-Smith) has been read through
Jung's archetypes — Shadow, Anima/Animus, Self, Hero, Trickster — since
essentially the mid-20th century. This is about universal narrative
patterns, not a trait-keyword taxonomy with facets and loadings the way
OCEAN is.

**Adjacent computational work, not the same thing:** a public Kaggle
dataset of all 78 cards' meanings exists for NLP use, and at least one
hobbyist writeup ("Uncovering Tarot Biases with Simple NLP") ran
sentiment analysis, embeddings, and clustering over card-meaning text.
Neither maps that text onto Big Five or HEXACO facets specifically.

## What doesn't seem to exist

A systematic mapping of tarot card **keywords** onto a standard trait
**facet** taxonomy — the specific thing this session's question was
circling. The birth-card version has been tried and failed. The
keyword-to-trait-facet version looks genuinely untapped.

## What this means for us

Cuts both ways. We're not quietly re-deriving something already
established and validated — if we build a Trait↔Card correspondence,
it's a real design decision made on our own judgment, not an adoption of
existing literature. That also means there's nothing to lean on for
validation; we'd be asserting the correspondence, not measuring it. Worth
remembering if this ever gets framed as more than "a deliberate creative
structure for the data model" — the one real empirical test of something
adjacent came back negative.

Sources: see chat log 2026-08-18 for full citations (Armand's paper via
ANIMA Indonesian Psychological Journal and ResearchGate; MBTI/court-card
correspondence; Jungian archetype readings; the Kaggle dataset and NLP
writeup). Not re-listed here since none of them are primary sources for
*this* project's own data model — this file is a pointer for "was this
already done," not a citation index to build on.
