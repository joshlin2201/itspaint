# Instant Alpha

## Decision

Build Instant Alpha as a fourth Select mode. A click selects the contiguous
colour region under the pointer. The existing selection actions then crop,
invert, copy, cut, or delete that region, and a dedicated action clears it to
transparency.

This keeps the rail at twelve jobs and puts another way to select inside the
tool that owns selection. A separate rail tool would improve first-glance
visibility but break the rule that the rail lists jobs, not variations. Putting
the feature under Fill would reuse a familiar icon but misstate the outcome:
Instant Alpha selects pixels; it does not paint them.

## Experience

The user wants to remove a screenshot background without tracing it. The
working object is the connected colour region under the pointer. Clicking is
the primary action. Marching ants around the region's actual pixel boundary are
the first feedback; “Make transparent” is the outcome. The canvas pixels and
undo history do not change until the user chooses it.

The emotional tone is immediate and exact. The aesthetic direction is the
existing compact Mac paint grammar: one more SF Symbol in Select's segmented
control, the existing tolerance slider, and no new surface. The signature
moment is a single click that wraps a background—including holes—with marching
ants instead of a bounding box, followed by an undoable removal over a visible
transparency grid.

## Surface contract

- **User goal:** select a connected background or object by colour.
- **Object and state:** a canvas plus an optional masked selection.
- **Primary action:** choose Instant Alpha, then click a colour.
- **Feedback:** marching ants follow every exposed edge of the mask; cleared
  pixels reveal the transparency grid.
- **Grammar:** existing options panel, spacing tokens, typography, and selection
  actions; accent remains reserved for the active option.
- **Media fit:** the selection is expressed in integer canvas pixels at every
  zoom.
- **Layer contract:** the outline is drawn in the canvas overlay; it creates no
  window, popover, or portal and never intercepts input.
- **States:** no selection, selected region, whole-canvas region, region with a
  hole, tolerant match, out-of-bounds click, and Escape/deselect.

## Implementation

1. Extract the fill tool's iterative span walk into a read-only
   `Raster.floodSelection` primitive. Keep `floodFill` as a thin mutation over
   the returned `Selection`, preserving its existing behaviour.
2. Add `instantAlpha` to `SelectionKind` and route a Select click to the new
   engine selection command. Give it its own clamped tolerance setting so Fill
   and Select do not change one another silently.
3. Draw masked selections from their true pixel-edge contour. Cache the path by
   selection and zoom so marching-ant animation does not rebuild it each frame.
4. Add the Select-mode control, tolerance slider, Shift-add and Option-subtract
   modifiers, “Make transparent” action, checkerboard alpha feedback, and a
   one-line gesture hint.
5. Cover flood selection, engine behaviour, alpha removal, tolerance, no-undo
   semantics, combination gestures, the transparency grid, and the
   non-rectangular canvas outline. Update the feature and roadmap docs with the
   same vocabulary.

## Quality gates

The change reuses the existing tokenized controls and introduces no colour,
spacing, radius, elevation, or animation values. It adds no customer-facing
claim, network work, storage, schema, modal, or destructive action. The full
engine and app suites must stay green, and the running app must be inspected at
normal and magnified zoom.

## Design checks

Two details make the interaction match its promise:

- The marquee follows the true mask contour. A bounding box would misrepresent
  the selected pixels.
- The mode keeps the familiar name “Instant Alpha,” while its hint states the
  action plainly: “Click · ⇧ add · ⌥ subtract.”

## Research input

Apple's current Preview guide leads with one-click background removal, while
older Instant Alpha asks users to drag a colour range and then press Delete.
User reports repeatedly expose three gaps in that older flow: clicking without
dragging appears to do nothing, complex backgrounds require repeated
select-delete cycles, and saved transparency can be hard to verify. This design
keeps deterministic colour selection for screenshot work but removes those
frictions with one-click selection, explicit tolerance, add/subtract modifiers,
a named transparency action, and visible alpha.
