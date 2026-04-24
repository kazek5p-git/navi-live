# Shared Product Rules

This directory is the first step toward a shared cross-platform core without rewriting the native UI layers.

Current source of truth:

- [product-rules.json](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/shared/product-rules.json)

Generator:

- [generate-shared-product-rules.py](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/scripts/generate-shared-product-rules.py)

Generated platform files:

- [SharedProductRules.kt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/android/app/src/main/java/com/navilive/android/model/SharedProductRules.kt)
- [SharedProductRules.swift](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Sources/Core/Models/SharedProductRules.swift)

Current shared scope:

- countdown milestones before a maneuver
- immediate turn instruction thresholds
- maneuver advance thresholds
- off-route thresholds
- auto-recalculation cooldown
- nearby/global search limits and radii
- search ranking weights and distance bands
- walking ETA heuristic for search results
- address field priority and house-number normalization patterns
- supported turn modifier set

Workflow:

1. Edit `shared/product-rules.json`.
2. Run `python .\\scripts\\generate-shared-product-rules.py`.
3. Build Android and iOS to verify the generated files still compile.

The native Android and iOS UIs remain separate on purpose.
Only product rules that benefit from one source of truth should move here.
