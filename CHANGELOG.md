# Changelog

All notable changes to Salieri will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Fix time signature meta event parsing (-10855 error)
- Add support for lyrics and text elements
- Implement slurs and ties
- Add advanced beaming rules
- Support for custom music fonts

## [1.0.0] - 2025-01-28

### Added
- **Core Functionality**
  - MIDI and MusicSequence parsing
  - Professional PDF sheet music generation
  - Cross-platform support (macOS 13.5+, iOS 17.0+)

- **Music Notation Support**
  - Notes and rests with all standard durations
  - Microtonal accidentals (quarter-sharp, quarter-flat, etc.)
  - Time signatures and key signatures
  - Clefs (treble, bass, alto, tenor, percussion)
  - Automatic stem direction
  - Basic beaming for eighth and sixteenth notes
  - Ledger lines for notes outside the staff

- **Layout and Engraving**
  - Automatic measure grouping
  - Multi-page pagination
  - Configurable page sizes and margins
  - Staff positioning and spacing
  - Part extraction support

- **API and Configuration**
  - `Salieri` main class with simple API
  - `SalieriConfiguration` for customizing output
  - Support for both MusicSequence and MIDI file input
  - Professional PDF output using Core Graphics

- **Testing and Documentation**
  - Comprehensive test suite covering all core functionality
  - Complete API documentation with examples
  - Cross-platform compatibility verification
  - MIT License and contribution guidelines

### Technical Details
- Built with Swift 5.9+ and Xcode 15.0+
- Uses Core Graphics and PDFKit for rendering
- AudioToolbox integration for MIDI processing
- Modular architecture for extensibility
- No third-party dependencies

### Known Issues
- Time signature meta events fail to parse (error -10855)
- Basic beaming implementation (advanced rules planned)
- Limited text element support
- No support for slurs, ties, or articulations yet

---

## Version History

### 1.0.0 (Initial Release)
- Complete MIDI to PDF pipeline
- Professional engraving quality
- Cross-platform compatibility
- Comprehensive test coverage
- Full documentation and licensing 