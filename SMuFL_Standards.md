# SMuFL Standards & Glyph Registration Guidelines

## Overview

This document contains the official Standard Music Font Layout (SMuFL) sizing standards and glyph registration guidelines for implementing professional music notation rendering.

**Source**: [SMuFL Specification - Metrics and Glyph Registration](https://w3c.github.io/smufl/latest/specification/scoring-metrics-glyph-registration.html)

## Core Sizing Principles

### Staff Space = 0.25 em
- **One staff space** = 0.25 em (em square)
- **Five-line staff** = 1.0 em total height
- **Staff line spacing** = 0.25 em
- **Coordinate system**: Origin (0,0) = middle of bottom staff line

### Font Design Units
- **PostScript fonts**: 1000 upm (design units per em) → 1 staff space = 250 design units
- **TrueType fonts**: 2048 upm → 1 staff space = 512 design units

## Glyph Registration Rules

### Noteheads
- **Positioned as if on bottom line** of staff
- **Vertically centered** on baseline (y=0)
- **Leftmost point** at x=0
- **Width**: Approximately 0.6 staff spaces
- **Height**: Approximately 0.6 staff spaces

### Stems
- **Pointing upwards** from notehead on bottom line
- **Center of stem** at x=0
- **Normal stem length**: 3.5 staff spaces
- **Stem width**: 0.08 staff spaces (very thin)

### Accidentals
- **Positioned as if applying to notehead on bottom line**
- **Vertically centered** on baseline
- **Height**: Approximately 2 staff spaces
- **Width**: Approximately 1 staff space

### Clefs
- **Pitch reference** on baseline (e.g., F clef dots above/below baseline)
- **Visual center** for non-pitch clefs
- **Height**: Approximately 3 staff spaces
- **Width**: Approximately 2 staff spaces

### Time Signatures
- **Digits**: 2 staff spaces tall (0.5 em)
- **Vertically centered** on baseline
- **Non-zero side bearings** for good spacing
- **Large symbols** (+, common time, cut time): vertically centered on baseline

### Rests
- **Relative to imaginary staff position** (usually center line)
- **Font baseline** represents staff position
- **Whole note rest**: hangs from font baseline

### Flags
- **y=0**: end of stem of normal length
- **x=0**: left-hand side of stem

### Articulations
- **Above notes**: positioned to sit on baseline (y=0)
- **Below notes**: positioned to hang from baseline

## Implementation Guidelines

### Sizing Strategy
```swift
// SMuFL specification: one staff space = 0.25 em
let emSize = staffLineSpacing * 4.0 // 1 em = 4 staff spaces
let noteSize = emSize // Size entire glyph to 1 em (SMuFL standard)
```

### Positioning Strategy
```swift
// SMuFL: Noteheads positioned as if on bottom line of staff
// Noteheads are vertically centered on baseline (y=0)
yOffset = symbolSize / 2
```

### Symbol-Specific Sizing
```swift
// Notes: 1 em (4 staff spaces)
let noteSize = staffLineSpacing * 4.0

// Clefs: 3 staff spaces
let clefSize = staffLineSpacing * 3.0

// Accidentals: 2 staff spaces
let accidentalSize = staffLineSpacing * 2.0

// Time signatures: 2 staff spaces
let timeSignatureSize = staffLineSpacing * 2.0
```

## Coordinate System

### Font Design Space
- **Origin (0,0)**: middle of bottom staff line
- **y = 1 em**: middle of top staff line
- **x = 0**: leftmost point of glyphs
- **Staff height**: 1.0 em (4 staff spaces)

### Glyph Registration
- **Zero-width side bearings** for most glyphs
- **Non-zero side bearings** for:
  - Time signature digits
  - Dynamics letters
  - Figured bass digits
  - Parentheses
- **Negative side bearings** for tessellating glyphs

## Special Cases

### Dynamics
- **Caps height**: around 0.5 em
- **x-height**: around 0.25 em
- **Non-zero side bearings** for good spacing

### Bracket Ends
- **Connection point** to vertical bracket at y=0

### Stem Decorations
- **Visual center** of symbol at x=0 and y=0

### Combining Glyphs
- **Designed to be superimposed** on stems
- **Center point** at stem center

## Best Practices

### Font Selection
- Use SMuFL-compliant fonts (e.g., Bravura)
- Ensure proper Unicode mapping
- Verify glyph registration

### Sizing Consistency
- Always use staff line spacing as base unit
- Scale entire glyphs, not individual components
- Maintain proportional relationships

### Positioning Accuracy
- Position noteheads at staff line intersections
- Align accidentals with noteheads
- Center clefs on staff

### Quality Assurance
- Test with various staff sizes
- Verify symbol proportions
- Check for overlapping or gaps

## References

- [SMuFL Official Specification](https://w3c.github.io/smufl/latest/specification/)
- [SMuFL Glyph Tables](https://w3c.github.io/smufl/latest/specification/glyph-tables.html)
- [Bravura Font](https://www.smufl.org/fonts/)
- [W3C Music Notation Community Group](https://www.w3.org/community/music-notation/)

---

*Last updated: July 28, 2025*
*Based on SMuFL specification version: Latest* 