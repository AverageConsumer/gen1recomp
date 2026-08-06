# RFC 0002 — Let mods hide an active screen state from the main render

## Status

Proposed. Engine: `StateStack.lua`, `Game.lua`. Tests:
`screen_render_visible.lua`.

## Motivation

A mod can render a native menu on a companion display through
`render.compose`, but it cannot remove that menu from the main display without
also popping it. Popping transfers update and input ownership and forces the
mod to reimplement native menu behavior.

## The decision it extends

No prior D-number. Extends the render-hook plan in `docs/modding.md` and the
state-stack rendering contract in `docs/architecture.md`.

## The exact API delta

Backward-compatible, additive-only.

### `screen.render_visible`

New hook called with `(state) -> boolean` through the public wrapper signature
`(next, state)`. Its vanilla result is `true`.

Returning `false` excludes the state from the main draw, from opaque-base
selection and from palette-zone ownership. It does not remove the state or
change update, input, push or pop behavior. The call sites are
`StateStack:visibleBase`, `StateStack:draw` and the equivalent draw and palette
walks in `Game:draw`.

The hook is guarded by `Runtime.wantsHook`, so the no-subscriber path allocates
nothing. It is a pure render predicate and may be evaluated more than once per
frame.

## Migration note for existing mods

**Nothing.** With no subscriber every state remains visible, and the existing
state-stack, event and hook behavior is unchanged.

## Parity tests

- **No-mod:** the topmost opaque state still owns drawing and palette zones,
  and `Runtime.wantsHook("screen.render_visible")` stays false.
- **Mod-API:** a fixture mod registers through `mod.hooks:wrap`, hides one
  opaque state and proves the state beneath draws and owns the palette while
  the hidden state remains topmost and continues updating.

## Deprecation etiquette

Nothing deprecated. This is one additive hook with a `true` vanilla default.
