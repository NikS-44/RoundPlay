# RoundPlay

Golf betting games, scored on the course.

## Layout

- `Packages/RoundPlayEngine/` — pure Swift scoring engine. No UI, no I/O. `swift test` to verify.
- `RoundPlay/` — iOS app target. Generated project; run `xcodegen generate` after editing `project.yml`.
- `docs/specs/` — design documents.
- `docs/plans/` — implementation plans.

## Building

```bash
brew install xcodegen     # once
xcodegen generate         # regenerate RoundPlay.xcodeproj
open RoundPlay.xcodeproj
```

## Testing the engine

```bash
cd Packages/RoundPlayEngine && swift test
```
