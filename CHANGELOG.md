# Changelog

## [1.0.0] — 2026-03-04

### Added
- CRope2D node — 2D rope physics simulation
  - Verlet integration with configurable stiffness and damping
  - Collision support (StaticBody2D, RigidBody2D, CharacterBody2D)
  - Anchor system (start, end, both, none)
  - Modular architecture with four module types:
    - **Force modules** — gravity, magnet, wind
    - **Line modules** — smooth, simplify, subdivide
    - **Render modules** — direct, Line2D, debug
    - **Break modules** — rope breaking under tension
  - Platform support: macOS, Linux, Windows, Web
  - 13 example scenes demonstrating all features
  - 10 custom GDScript module examples
  - Complete API documentation
