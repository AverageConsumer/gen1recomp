# Rulesets

**OPTIONS > RULESET** picks which set of Gen 1 battle behaviors to run. Both
rulesets share the same damage formulas; they differ only in whether the
original's quirks are kept. The setting persists in `options.lua`, and mods
can register their own.

## gen1_faithful

The default. Reproduces the original cartridge, famous bugs included.

| Rule                        | Behavior                                              |
| --------------------------- | ----------------------------------------------------- |
| `oneIn256Miss`              | A 100%-accurate move still misses on a roll of 255     |
| `critUsesBaseSpeed`         | Crit rate reads base speed, not the current stat       |
| `critIgnoresStages`         | Crit rate ignores stat stages                          |
| `focusEnergyBug`            | FOCUS ENERGY quarters the crit rate instead of x4      |
| `enemyUnlimitedPP`          | Enemies never spend PP, so they never Struggle         |
| `hyperBeamSkipRechargeOnKO` | HYPER BEAM skips its recharge when the target faints   |
| `substituteZeroHpBug`       | SUBSTITUTE at exactly 1/4 HP goes up, then the user faints |
| `randMin` / `randMax`       | Damage random factor 217-255                           |

## modern_clean

Keeps the formulas but removes the notorious quirks.

| Rule                        | Behavior                                              |
| --------------------------- | ----------------------------------------------------- |
| `oneIn256Miss`              | Off: a 100%-accurate move always hits                  |
| `critUsesBaseSpeed`         | Unchanged: crit rate still reads base speed            |
| `critIgnoresStages`         | Off: stat stages count toward the crit rate            |
| `focusEnergyBug`            | Off: FOCUS ENERGY raises the crit rate as intended     |
| `enemyUnlimitedPP`          | Off: enemies deplete PP and Struggle when empty        |
| `hyperBeamSkipRechargeOnKO` | Off: HYPER BEAM always recharges, like Gen 2+          |
| `substituteZeroHpBug`       | Off: SUBSTITUTE fails at exactly 1/4 HP, like Gen 2+   |
| `randMin` / `randMax`       | Damage random factor 217-255, same as faithful         |
