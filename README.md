# Salieri

A Swift package for parsing MIDI signals and generating professional-quality PDF sheet music. Salieri ingests MusicSequences from the AudioToolbox API and outputs perfect music scores with comprehensive notation including keys, time signatures, stems, beams, ledger lines, clefs, chords, and microtonal accidentals.

## Features

- **Professional Engraving Quality**: Output comparable to Sibelius, Finale, and Dorico
- **Complete Notation Support**: 
  - Notes, rests, accidentals (including microtonal)
  - Time signatures, key signatures, clefs
  - Stems, beams, ledger lines
  - Automatic measure grouping and pagination
- **Multiple Input Sources**: MusicSequence objects and MIDI files
- **Flexible Output**: Full scores and individual parts
- **Cross-Platform**: macOS 13.5+ and iOS 17.0+
- **Extensible Architecture**: Designed for future notation features

## Requirements

- macOS 13.5+ / iOS 17.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add Salieri to your project in Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select the version you want to use

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/Salieri.git", from: "1.0.0")
]
```

## Quick Start

### Basic Usage

```swift
import Salieri
import AudioToolbox

// Create a Salieri instance with default configuration
let salieri = Salieri()

// Generate PDF from a MusicSequence
if let pdf = salieri.renderPDF(from: musicSequence) {
    // Save or display the PDF
    let data = pdf.dataRepresentation()
    try data?.write(to: outputURL)
}
```

### MIDI File Processing

```swift
import Salieri

let salieri = Salieri()

// Generate PDF from a MIDI file
if let pdf = salieri.renderPDF(fromMIDIFileAt: midiFileURL) {
    // Process the generated PDF
    print("PDF generated successfully with \(pdf.pageCount) pages")
}
```

## Configuration

### Custom Page Layout

```swift
import Salieri

// Configure page size, margins, and staff size
let config = SalieriConfiguration(
    pageSize: CGSize(width: 595.2, height: 841.8), // A4
    margins: EdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
    staffSize: 7.0,
    renderParts: false,
    renderFullScore: true
)

let salieri = Salieri(configuration: config)
```

### Advanced Configuration Options

```swift
let config = SalieriConfiguration(
    pageSize: CGSize(width: 612, height: 792), // Letter size
    margins: EdgeInsets(top: 50, left: 50, bottom: 50, right: 50),
    staffSize: 8.0, // Larger staff for better readability
    renderParts: true, // Generate individual parts
    renderFullScore: true // Generate full score
)
```

## API Reference

### SalieriConfiguration

```swift
public struct SalieriConfiguration {
    public var pageSize: CGSize           // PDF page dimensions
    public var margins: EdgeInsets        // Page margins
    public var staffSize: CGFloat         // Staff line spacing
    public var renderParts: Bool          // Generate individual parts
    public var renderFullScore: Bool      // Generate full score
}
```

### Salieri

```swift
public class Salieri {
    public let configuration: SalieriConfiguration
    
    public init(configuration: SalieriConfiguration = SalieriConfiguration())
    
    // Render PDF from MusicSequence
    public func renderPDF(from sequence: MusicSequence) -> PDFDocument?
    
    // Render PDF from MIDI file
    public func renderPDF(fromMIDIFileAt url: URL) -> PDFDocument?
}
```

## Advanced Usage

### Working with MusicSequences

```swift
import AudioToolbox
import Salieri

// Create a MusicSequence programmatically
var sequence: MusicSequence?
NewMusicSequence(&sequence)

if let seq = sequence {
    // Add tracks and events to the sequence
    var track: MusicTrack?
    MusicSequenceNewTrack(seq, &track)
    
    // Add notes, meta events, etc.
    // ...
    
    // Generate PDF
    let salieri = Salieri()
    if let pdf = salieri.renderPDF(from: seq) {
        // Process PDF
    }
}
```

### Batch Processing

```swift
import Salieri

let salieri = Salieri()
let midiFiles = [/* array of MIDI file URLs */]

for midiFile in midiFiles {
    if let pdf = salieri.renderPDF(fromMIDIFileAt: midiFile) {
        let outputURL = midiFile.deletingPathExtension().appendingPathExtension("pdf")
        try pdf.dataRepresentation()?.write(to: outputURL)
    }
}
```

## Supported Notation Features

### Notes and Rests
- All standard note durations (whole, half, quarter, eighth, sixteenth, etc.)
- Dotted notes and custom durations
- Rests with automatic detection
- Microtonal accidentals (quarter-sharp, quarter-flat, etc.)

### Notation Elements
- **Clefs**: Treble, bass, alto, tenor, percussion
- **Time Signatures**: All common meters with proper formatting
- **Key Signatures**: Major and minor keys with correct accidentals
- **Stems**: Automatic direction based on note position
- **Beams**: Automatic grouping of eighth and sixteenth notes
- **Ledger Lines**: Automatic placement for notes outside the staff

### Layout Features
- **Automatic Pagination**: Multi-page scores with proper page breaks
- **Measure Grouping**: Proper measure boundaries and line breaks
- **Staff Positioning**: Correct vertical spacing and alignment
- **Part Extraction**: Individual instrument parts (when enabled)

## Platform Support

### macOS
- Full support for all features
- Uses Core Graphics and PDFKit for rendering
- Supports both MusicSequence and MIDI file input

### iOS
- Full support for all features
- Optimized for mobile rendering
- Compatible with iOS 17.0 and later

## Architecture

Salieri is built with a modular architecture:

1. **Input Layer**: Parses MusicSequence and MIDI files
2. **Music Model**: Internal representation of score data
3. **Engraving Engine**: Converts music data to layout
4. **PDF Renderer**: Generates final PDF output

This design allows for easy extension and customization of individual components.

## Contributing

Salieri is designed to be extensible. Future features planned include:
- Lyrics and text elements
- Articulations and dynamics
- Slurs and ties
- Guitar tablature
- Advanced beaming rules
- Custom fonts and glyphs

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### License Summary

The MIT License is a permissive license that allows you to:
- Use the software for any purpose
- Modify the software
- Distribute the software
- Use it commercially
- Sublicense it

The only requirement is that you include the original copyright and license notice in any copy of the software/source.

### Attribution

If you use Salieri in your project, please include attribution in your documentation:

```
Salieri - Professional MIDI to PDF Sheet Music Generator
Copyright (c) 2025 Salieri Contributors
Licensed under MIT License
```

## Acknowledgments

Salieri is named after Antonio Salieri, the classical composer and teacher. The package aims to bring the same level of precision and artistry to digital music engraving that Salieri brought to classical composition. 