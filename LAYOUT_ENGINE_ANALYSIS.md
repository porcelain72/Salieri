# Salieri Layout Engine Analysis

## Overview

The Salieri layout engine is a sophisticated music notation rendering system that transforms MIDI data into professionally formatted PDF scores. This document provides a detailed breakdown of every step in the layout process.

## Architecture Overview

The layout engine consists of three main components:
1. **SalieriEngraver** - Core layout logic and measure organization
2. **SalieriPDFRenderer** - PDF generation and drawing
3. **SalieriSMuFLRenderer** - Musical symbol rendering using SMuFL font

## Detailed Layout Process

### Phase 1: Initial Setup and Configuration

#### Step 1.1: Configuration Parameters
```swift
let systemSpacing: CGFloat = 40.0 // Space between systems
let staffSpacing: CGFloat = 35.0 // Space between staves in multi-track scores
let staffLineSpacing: CGFloat = config.staffSize * 1.0 // Reduced by one third
let staffLines = 5
let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
```

**Purpose**: Establishes fundamental spacing and sizing parameters for the entire layout.

#### Step 1.2: Available Space Calculation
```swift
let availableHeight = config.pageSize.height - config.margins.top - config.margins.bottom
let availableWidth = config.pageSize.width - config.margins.left - config.margins.right
```

**Purpose**: Calculates the usable area on each page after accounting for margins.

#### Step 1.3: System Capacity Calculation
```swift
let systemHeight = CGFloat(score.parts.count) * staffSpacing + staffHeight
let systemsPerPage = max(1, Int(availableHeight / (systemHeight + systemSpacing)))
```

**Purpose**: Determines how many systems can fit on each page based on available height and system spacing.

### Phase 2: Measure Width Calculation

#### Step 2.1: First Measure Special Handling
```swift
let clefWidth = staffHeight * 0.9
let timeSignatureWidth = staffHeight * 0.8 * 2
let keySignatureWidth = staffHeight * 0.6 * 0 // No key signature for now
let firstMeasureMinWidth = clefWidth + timeSignatureWidth + keySignatureWidth + staffHeight * 2.0
```

**Purpose**: Reserves space in the first measure for clef, time signature, and key signature elements.

#### Step 2.2: Note Content Analysis
For each measure in each part:
```swift
let noteCount = measure.events.compactMap { event in
    if case .note(_) = event { return event }
    return nil
}.count

let noteSpacing = minNoteSpacing * CGFloat(noteCount - 1)
let noteWidths = measure.events.compactMap { event in
    if case let .note(note) = event {
        return calculateNoteWidth(for: note, staffHeight: staffHeight)
    }
    return nil
}
let totalNoteWidth = noteWidths.reduce(0, +)
let measureNoteWidth = totalNoteWidth + noteSpacing
```

**Purpose**: Calculates the total width needed for all notes in a measure plus spacing between them.

#### Step 2.3: Measure Width Assignment
```swift
if measureIndex == 0 {
    measureWidth = max(measureWidth, firstMeasureMinWidth + measureNoteWidth)
} else {
    measureWidth = max(measureWidth, measureNoteWidth)
}
measureWidth = max(measureWidth, staffHeight * 3.0) // Minimum width
```

**Purpose**: Assigns final width to each measure, ensuring minimum width requirements are met.

### Phase 3: System Grouping

#### Step 3.1: Measure-to-System Assignment
```swift
while currentMeasure + measuresInSystem < measureWidths.count {
    let nextMeasureWidth = measureWidths[currentMeasure + measuresInSystem]
    if systemWidth + nextMeasureWidth <= availableWidth {
        systemWidth += nextMeasureWidth
        measuresInSystem += 1
    } else {
        break
    }
}
```

**Purpose**: Groups measures into systems that fit within the available page width.

#### Step 3.2: System Width Stretching
```swift
let stretchedSystemWidth = availableWidth
systems.append((startIndex: currentMeasure, endIndex: currentMeasure + measuresInSystem, systemWidth: stretchedSystemWidth))
```

**Purpose**: Stretches each system to fill the full available width for professional appearance.

### Phase 4: Page Organization

#### Step 4.1: System-to-Page Assignment
```swift
let pagesOfSystems = stride(from: 0, to: systems.count, by: systemsPerPage).map { startIndex in
    let endIndex = min(startIndex + systemsPerPage, systems.count)
    return Array(systems[startIndex..<endIndex])
}
```

**Purpose**: Distributes systems across pages based on calculated system capacity.

#### Step 4.2: Page Creation
```swift
for (_, pageSystems) in pagesOfSystems.enumerated() {
    var pageSystemsList: [SalieriSystem] = []
    // ... system creation logic
    let page = SalieriPage(systems: pageSystemsList, pageNumber: currentPage)
    pages.append(page)
}
```

**Purpose**: Creates page objects containing the assigned systems.

### Phase 5: Staff and Measure Layout

#### Step 5.1: Clef Selection
```swift
let clef = selectClefForPart(part)
// Logic: average MIDI note < 50 → bass clef, else treble clef
```

**Purpose**: Automatically selects appropriate clef based on the pitch range of notes in each part.

#### Step 5.2: Measure Distribution
```swift
let partMeasures: [SalieriMeasure]
if measureStart < part.measures.count {
    let endIndex = min(measureEnd, part.measures.count)
    partMeasures = Array(part.measures[measureStart..<endIndex])
} else {
    partMeasures = []
}
```

**Purpose**: Extracts the measures that belong to each part within the current system.

#### Step 5.3: Measure Stretching and Positioning
```swift
let measuresInSystem = partMeasures.count
let stretchedMeasureWidth = systemWidth / CGFloat(measuresInSystem)

let measures = partMeasures.enumerated().map { (index, measure) in
    let originalMeasureWidth = measureWidths[measureStart + index]
    let measureLayout = createMeasureLayout(measure, localMeasureIndex: index, measureWidth: originalMeasureWidth, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight, clef: clef)
    
    // Scale note positions proportionally
    let scaleFactor = stretchedMeasureWidth / originalMeasureWidth
    let scaledEvents = measureLayout.events.map { notehead in
        SalieriNotehead(
            note: notehead.note,
            x: notehead.x * scaleFactor,
            y: notehead.y,
            // ... other properties
        )
    }
    
    let xPosition = CGFloat(index) * stretchedMeasureWidth
    return SalieriMeasureLayout(events: scaledEvents, xPosition: xPosition, width: stretchedMeasureWidth, measureNumber: measureLayout.measureNumber)
}
```

**Purpose**: Stretches measures to fill system width and scales note positions proportionally.

### Phase 6: Note Positioning

#### Step 6.1: Vertical Position Calculation
```swift
let y = yForPitch(note.pitch, clef: clef, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight)
// Logic: C4 (MIDI 60) positioned at staffHeight + staffLineSpacing + staffHeight/2.0
// Each semitone offset moves note by staffLineSpacing/2
```

**Purpose**: Calculates the vertical position of each note on the staff based on its pitch and the selected clef.

#### Step 6.2: Horizontal Position Calculation
```swift
let xPosition = calculateNotePosition(for: note, measureIndex: eIdx, measureWidth: measureWidth, totalNotes: measure.events.count, isFirstMeasure: localMeasureIndex == 0, staffHeight: staffHeight)

// For first measure: reserve space for clef, time signature, key signature
// For all measures: position based on note index and minimum spacing
```

**Purpose**: Calculates the horizontal position of each note within its measure.

#### Step 6.3: Ledger Line Calculation
```swift
let ledgerLines = ledgerLinesForPitch(note.pitch, clef: clef, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight)
// Logic: Calculate theoretical Y position, determine count of ledger lines needed
// Position ledger lines at exact staff line positions above/below staff
```

**Purpose**: Determines the number and position of ledger lines for notes outside the staff.

#### Step 6.4: Stem Direction Assignment
```swift
let stemDirection: SalieriStemDirection = y > staffHeight / 2 ? .up : .down
```

**Purpose**: Assigns stem direction based on note position relative to the middle of the staff.

### Phase 7: PDF Rendering

#### Step 7.1: PDF Context Setup
```swift
let pdfData = NSMutableData()
let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
var mediaBox = CGRect(origin: .zero, size: config.pageSize)
guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
```

**Purpose**: Initializes the PDF rendering context and data structures.

#### Step 7.2: Page Rendering Loop
```swift
for page in layout.pages {
    pdfContext.beginPage(mediaBox: &mediaBox)
    pdfContext.saveGState()
    pdfContext.translateBy(x: 0, y: config.pageSize.height)
    pdfContext.scaleBy(x: 1, y: -1) // Flip for correct orientation
    
    drawPageMargin(context: pdfContext, rect: mediaBox, margins: config.margins)
    
    for system in page.systems {
        drawSystem(system, context: pdfContext, config: config)
    }
    
    pdfContext.restoreGState()
    pdfContext.endPage()
}
```

**Purpose**: Renders each page with proper coordinate system transformation.

#### Step 7.3: Staff Line Drawing
```swift
for i in 0..<staffLines {
    let y = yBase + CGFloat(i) * staffLineSpacing
    context.move(to: CGPoint(x: config.margins.left, y: y))
    context.addLine(to: CGPoint(x: config.pageSize.width - config.margins.right, y: y))
}
context.strokePath()
```

**Purpose**: Draws the five horizontal staff lines across the full page width.

#### Step 7.4: Clef and Time Signature Rendering
```swift
if let firstMeasure = staff.measures.first {
    let firstMeasureX = config.margins.left + firstMeasure.xPosition
    let clefX = firstMeasureX + config.staffSize * 2.0 + staffHeight * 0.2
    let clefY = yBase + staffHeight / 2
    drawClef(staff.clef, at: CGPoint(x: clefX, y: clefY), context: context, config: config)
    
    let timeSigX = clefX + config.staffSize * 4.0
    let timeSigY = yBase + staffHeight / 2
    drawTimeSignature(firstMeasure, at: CGPoint(x: timeSigX, y: timeSigY), context: context, config: config)
}
```

**Purpose**: Renders clef and time signature within the first measure of each staff.

#### Step 7.5: Measure and Note Rendering
```swift
for measure in staff.measures {
    drawMeasure(measure, yBase: yBase, context: context, config: config)
}

// Within drawMeasure:
for notehead in measure.events {
    let noteX = xStart + notehead.x
    drawNotehead(notehead, xBase: noteX, yBase: yBase, context: context, config: config)
}
```

**Purpose**: Renders each measure with its contained notes at calculated positions.

### Phase 8: SMuFL Symbol Rendering

#### Step 8.1: Font Initialization
```swift
static func initializeSMuFLFont() {
    if let fontURL = Bundle.module.url(forResource: "Bravura", withExtension: "otf"),
       let fontData = try? Data(contentsOf: fontURL),
       let provider = CGDataProvider(data: fontData as CFData),
       let font = CGFont(provider) {
        
        CTFontManagerRegisterGraphicsFont(font, &error)
        smuflFont = font
    }
}
```

**Purpose**: Loads and registers the SMuFL font for musical symbol rendering.

#### Step 8.2: Symbol Rendering
```swift
static func drawSMuFLSymbol(_ symbol: String, at point: CGPoint, context: CGContext, config: SalieriConfiguration, size: CGFloat) {
    guard let unicode = smuflUnicode(for: symbol),
          let font = smuflFont else { return }
    
    let fontDescriptor = CTFontDescriptorCreateWithNameAndSize("Bravura" as CFString, size)
    let ctFont = CTFontCreateWithFontDescriptor(fontDescriptor, 0, nil)
    
    let string = String(UnicodeScalar(unicode)!)
    let attributedString = NSAttributedString(string: string, attributes: [.font: ctFont])
    let line = CTLineCreateWithAttributedString(attributedString)
    
    context.textPosition = point
    CTLineDraw(line, context)
}
```

**Purpose**: Renders individual musical symbols using the SMuFL font at specified positions and sizes.

## Key Algorithms and Formulas

### 1. Pitch to Staff Position Mapping
```swift
let midiNumber = midiNumberForPitch(pitch)
let c4 = 60
let offset = c4 - midiNumber
let c4Position = staffHeight + staffLineSpacing + staffHeight/2.0
let y = c4Position + CGFloat(offset) * (staffLineSpacing / 2)
```

### 2. Ledger Line Calculation
```swift
let theoreticalY = theoreticalC4Position + CGFloat(offset) * (staffLineSpacing / 2)
if theoreticalY < 0 { // Above staff
    let count = Int(abs(theoreticalY) / staffLineSpacing)
    for i in 0..<count {
        let ledgerLineY = -CGFloat(i+1) * staffLineSpacing
    }
} else if theoreticalY > staffHeight { // Below staff
    let count = Int((theoreticalY - staffHeight) / staffLineSpacing)
    for i in 0..<count {
        let ledgerLineY = staffHeight + CGFloat(i+1) * staffLineSpacing
    }
}
```

### 3. Measure Width Calculation
```swift
let baseWidth = staffLineSpacing * 0.6 // SMuFL note head width
let durationMultiplier: CGFloat = // varies by note duration
return baseWidth * durationMultiplier
```

### 4. System Stretching
```swift
let stretchedMeasureWidth = systemWidth / CGFloat(measuresInSystem)
let scaleFactor = stretchedMeasureWidth / originalMeasureWidth
let scaledX = originalX * scaleFactor
```

## Performance Considerations

1. **Font Caching**: SMuFL font is loaded once and cached for reuse
2. **Measure Width Pre-calculation**: All measure widths are calculated upfront
3. **System Grouping**: Measures are grouped into systems in a single pass
4. **Proportional Scaling**: Note positions are scaled mathematically rather than recalculated

## Limitations and Future Improvements

1. **Beam Grouping**: Currently supports basic beam grouping but could be enhanced
2. **Tie and Slur Rendering**: Not yet implemented
3. **Dynamic Spacing**: Could implement more sophisticated spacing algorithms
4. **Multi-track Alignment**: Could improve alignment of simultaneous events across tracks
5. **Page Break Optimization**: Could implement more intelligent page breaking algorithms

## Conclusion

The Salieri layout engine implements a comprehensive music notation rendering system that handles the complex spatial relationships inherent in musical scores. The multi-phase approach ensures that each aspect of the layout (measure widths, system grouping, note positioning, and rendering) is handled systematically and efficiently. 