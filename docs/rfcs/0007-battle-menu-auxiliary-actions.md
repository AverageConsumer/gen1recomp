# RFC 0007: Battle menu auxiliary actions

## Status

Proposed.

## Problem

Tool mods can inspect/capture a persistent checkpoint only at a settled
ordinary wild/trainer player-decision boundary. Before this proposal, that
boundary had no public semantic input/action seam: `BattleState` consumed the
command loop directly. A mod could reach it only through private battle/input
internals, which would be unsafe and incompatible with controller/touch input.

## Contract

`mod.hooks:wrap("battle.menu_auxiliary", callback)` is called only when START
is pressed at the existing checkpoint-safe player-decision boundary. The
callback signature is:

```lua
function callback(next, game, context)
  -- context is { kind = "wild" } or { kind = "trainer" }
  -- return true after claiming START, otherwise return next(game, context)
end
```

The context is data-only. No live battle controller, input object, serializer,
or restoration primitive is exposed. A `true` result consumes START for that
fixed step without selecting a battle command. With no installed handler,
START is inert exactly as before. Hook priorities and error isolation are the
existing generic wrapper semantics: a throwing handler is skipped and cannot
advance battle state.

The engine reuses the same internal safety predicate as battle checkpoint
capture. Link, Safari, ghost/demo, unsupported origins, scripts, queues,
animations, messages, forced replacement/locked actions, and unsettled HP or
status presentation never invoke the hook.

## Compatibility and verification

The call is additive and no-op with no handler. ROM-free engine tests prove
wild/trainer delivery, cursor/turn preservation, and unsafe-phase refusal;
the mod-SDK fixture proves a loaded mod can consume the semantic action using
only its public hook facade. `gate_hooks` automatically includes the new call
site in no-mod parity coverage.
