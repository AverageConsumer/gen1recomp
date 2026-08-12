# RFC 0008 — Runtime mod option schema export

## Status

Proposed. Engine: `src/mods/Loader.lua`. Tests:
`tests/mod_loader_tests.lua`. This RFC defines an optional filesystem
contract; it does not require a native launcher or any other consumer.

## Motivation

A native launcher may want to present settings for installed mods before it
starts the game. Running every mod's entry chunk in that launcher just to
discover its settings would duplicate engine behavior and give the launcher
an unnecessary code-execution surface. The engine already has the authoritative
runtime schemas after mod loading, so it can publish a data-only snapshot for
platform shells that want one.

## The exact contract

After the mod loader has finished running entry chunks, it may write
`mod_option_schemas.json` beside `options.lua` in the same filesystem. The
document is a snapshot of the current boot; it is not a second settings store
and does not change how option values are read or written.

Version 1 has this shape:

```json
{
  "schema_version": 1,
  "mods": {
    "example": [
      {"key":"enabled","type":"toggle","label":"Enabled","default":true},
      {"key":"mode","type":"choice","label":"Mode","default":"safe",
       "choices":[["Safe","safe"],["Fast","fast"]]},
      {"key":"rate","type":"number","label":"Rate","default":5,
       "min":0,"max":10,"step":1},
      {"key":"name","type":"text","label":"Name","default":"","maxLen":12}
    ]
  }
}
```

`mods` is keyed by mod id. Its rows come from the runtime
`mod.options:define` schema, or from the legacy manifest `options_schema` file
when the runtime schema is absent. The supported row types are `toggle`,
`choice`, `number`, and `text`. Their optional fields retain the meanings
established by the existing in-game option UI: choices are `[label, value]`
pairs, numeric rows may provide `min`, `max`, and `step`, and text rows may
provide `maxLen`.

Only mods that are enabled and successfully loaded in the current boot are
included. A disabled or failed mod must not contribute rows. If an older
snapshot exists and the current boot has no schema-bearing mods, the producer
overwrites it with `{"schema_version":1,"mods":{}}`; this prevents stale
settings rows from surviving a disable or load failure. A fresh mod-free boot
does not create the file, and a filesystem without write support is tolerated.

The producer writes the snapshot after entry chunks and the final load set
have been established. Consumers must treat the file as untrusted input and
must not execute anything from it.

## Compatibility and versioning

The contract is optional on both sides. A native consumer may be absent, and
the engine continues normally if the file cannot be written. A native
consumer is not required to render, validate, or persist every supported row;
it may ignore an unknown row type or optional field.

For compatibility with files produced by the original unversioned prototype,
a missing `schema_version` means version 1. Consumers must ignore documents
with a newer version rather than guessing at their shape. Producers must bump
the version whenever they change the document shape or the meaning of an
existing field. Version 1 is therefore the legacy unversioned format as well
as the explicitly versioned format shown above.

## Migration note

Nothing. Existing mods, option values, and the in-game options UI are
unchanged. Platforms that do not consume `mod_option_schemas.json` have no
new integration requirement.

## Parity tests

`tests/mod_loader_tests.lua` verifies the explicit version, runtime and legacy
row round-tripping, enabled/disabled filtering, failed-mod filtering,
stale-snapshot clearing, and tolerance of a read-only filesystem.

## Deprecation etiquette

Nothing is deprecated. The unversioned file form remains readable as legacy
version 1; new producers write the explicit `schema_version` field.
