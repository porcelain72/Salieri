# Visual Testing Guide for Salieri PDF Output

## Overview

This guide explains how to test and validate the visual quality of PDF output from the Salieri package. The test suite now includes **4 visual regression tests** that generate sample PDFs for manual inspection.

## Generated Test PDFs

The visual regression tests generate the following PDF files in the temporary directory:

### 1. `visual_test_output.pdf`
- **Purpose**: Basic visual quality validation
- **Content**: C major scale (8 notes)
- **What to Check**:
  - ✅ Clef is visible and properly positioned
  - ✅ Staff lines are evenly spaced
  - ✅ Notes are properly sized and positioned
  - ✅ No overlapping or overprinting
  - ✅ Stems are correctly oriented

### 2. `scaling_test_output.pdf`
- **Purpose**: Test proper scaling and positioning
- **Content**: 4 quarter notes (C, D, E, F)
- **What to Check**:
  - ✅ Notes are evenly spaced horizontally
  - ✅ Vertical positioning matches pitch (C lowest, F highest)
  - ✅ Staff size is appropriate (not too large/small)
  - ✅ Margins are respected

### 3. `clef_time_test_output.pdf`
- **Purpose**: Test clef and time signature rendering
- **Content**: Simple score with clef and time signature
- **What to Check**:
  - ✅ Treble clef ("G") is visible and properly positioned
  - ✅ Time signature ("4/4") is visible after the clef
  - ✅ Clef and time signature are centered on the staff
  - ✅ Proper font size and positioning
  - ✅ Simple text characters for reliable rendering

### 4. `overprint_test_output.pdf`
- **Purpose**: Test note overprinting prevention
- **Content**: C major scale with eighth notes
- **What to Check**:
  - ✅ Notes don't overlap or overprint
  - ✅ Proper spacing between consecutive notes
  - ✅ Stems don't interfere with adjacent notes
  - ✅ Accidentals don't overlap with notes

### 5. `staff_wrapping_test.pdf`
- **Purpose**: Test staff wrapping and pagination
- **Content**: 20 measures (80 notes) spanning multiple pages
- **What to Check**:
  - ✅ Staffs wrap when they reach the edge of the page
  - ✅ Multiple systems per page (if space allows)
  - ✅ Multiple pages generated for long sequences
  - ✅ Proper page numbering and layout

### 6. `multi_track_wrapping_test.pdf`
- **Purpose**: Test multi-track staff wrapping
- **Content**: Melody (15 measures) and bass (12 measures) tracks
- **What to Check**:
  - ✅ Multiple tracks wrap together
  - ✅ Different track lengths handled correctly
  - ✅ Systems align across tracks
  - ✅ Proper pagination for complex scores
  - ✅ Melody: C4-G4 range (treble clef appropriate)
  - ✅ Bass: C3-F3 range (bass clef automatically selected)
  - ✅ Appropriate clefs for each track's note range

### 7. `bar_line_alignment_test.pdf`
- **Purpose**: Test bar line alignment with system edges
- **Content**: 6 measures in 2 systems (3 measures each)
- **What to Check**:
  - ✅ Bar lines align exactly with system edges
  - ✅ Each system contains integer number of measures
  - ✅ Staff lines end at system boundaries
  - ✅ No partial measures or misaligned bar lines

### 8. `systems_per_page_test.pdf`
- **Purpose**: Test professional system density per page
- **Content**: 24 measures (8 systems of 3 measures each)
- **What to Check**:
  - ✅ 4-6 systems per page (professional density)
  - ✅ Proper spacing between systems and staves
  - ✅ Efficient use of page space
  - ✅ Readable but compact layout

### 9. `clef_selection_test.pdf`
- **Purpose**: Test automatic clef selection for different note ranges
- **Content**: Two tracks with different note ranges
- **What to Check**:
  - ✅ Top track: C4-F4 (treble clef "G" automatically selected)
  - ✅ Bottom track: C3-F3 (bass clef "F" automatically selected)
  - ✅ Clefs are properly positioned and visible
  - ✅ No excessive ledger lines for typical note ranges
  - ✅ Professional clef selection based on note ranges
  - ✅ Simple text characters for reliable rendering

### 10. `note_positioning_test.pdf`
- **Purpose**: Test note positioning within measures
- **Content**: 4 quarter notes in a single measure
- **What to Check**:
  - ✅ Notes are evenly spaced within the measure
  - ✅ Notes align with measure boundaries
  - ✅ No note overlap or overprinting
  - ✅ Proper horizontal positioning relative to bar lines
  - ✅ Professional note spacing and layout

## How to Run Visual Tests

### Run All Visual Tests
```bash
swift test --filter "testVisualOutputQuality|testProperScalingAndPositioning|testClefAndTimeSignatureRendering|testNoteOverprintingPrevention|testStaffWrappingAndPagination|testMultiTrackStaffWrapping|testBarLineAlignmentWithSystemEdges|testSystemsPerPage|testClefSelectionForNoteRanges|testNotePositioningWithinMeasures"
```

### Run Individual Tests
```bash
# Basic visual quality
swift test --filter testVisualOutputQuality

# Scaling and positioning
swift test --filter testProperScalingAndPositioning

# Clef and time signature
swift test --filter testClefAndTimeSignatureRendering

# Overprinting prevention
swift test --filter testNoteOverprintingPrevention

# Staff wrapping and pagination
swift test --filter testStaffWrappingAndPagination

# Multi-track staff wrapping
swift test --filter testMultiTrackStaffWrapping

# Bar line alignment
swift test --filter testBarLineAlignmentWithSystemEdges

# Systems per page density
swift test --filter testSystemsPerPage

# Clef selection for note ranges
swift test --filter testClefSelectionForNoteRanges

# Note positioning within measures
swift test --filter testNotePositioningWithinMeasures
```

## Visual Quality Checklist

### ✅ **Essential Elements**
- [ ] **Clef**: Treble clef (𝄞) visible and properly positioned
- [ ] **Staff Lines**: 5 evenly spaced horizontal lines
- [ ] **Notes**: Elliptical noteheads with proper stems
- [ ] **Spacing**: No overlapping or overprinting
- [ ] **Scaling**: Appropriate size for the page

### ✅ **Note Positioning**
- [ ] **Vertical**: Notes positioned correctly on staff lines/spaces
- [ ] **Horizontal**: Even spacing between notes
- [ ] **Stems**: Up for notes below middle line, down for above
- [ ] **Accidentals**: Properly positioned to the left of notes

### ✅ **Layout Quality**
- [ ] **Margins**: Adequate margins around the staff
- [ ] **Staff Size**: Not too large or small
- [ ] **Line Weight**: Consistent stroke width
- [ ] **Proportions**: Notes proportional to staff size

## Common Visual Issues and Solutions

### Issue: Notes Too Large
**Symptoms**: Noteheads appear oversized relative to staff
**Solution**: Reduce `staffSize` in configuration
```swift
let config = SalieriConfiguration(staffSize: 6.0) // Smaller value
```

### Issue: Notes Overlapping
**Symptoms**: Notes appear on top of each other
**Solution**: Increase horizontal spacing in `drawMeasure`
```swift
let xOffset = CGFloat(index) * 50.0 // Increase from 40.0
```

### Issue: Staff Too Small
**Symptoms**: Staff lines are too close together
**Solution**: Increase `staffSize` in configuration
```swift
let config = SalieriConfiguration(staffSize: 10.0) // Larger value
```

### Issue: Clef Not Visible
**Symptoms**: No clef symbol appears
**Solution**: Check clef rendering in `drawClef` function
- Verify Unicode symbols are correct
- Check font size and positioning

### Issue: Notes Wrong Position
**Symptoms**: Notes don't align with expected pitch
**Solution**: Check `yForPitch` calculation
- Verify MIDI note number to pitch mapping
- Check staff line spacing calculation

## Testing Your Own MusicSequences

### 1. Create a Test Case
```swift
func testMyMusicSequence() {
    let sequence = createMusicSequence()
    let track = createMusicTrack(in: sequence)
    
    // Add your specific notes
    let myNotes = [60, 62, 64, 65, 67] // Your melody
    for (i, noteNumber) in myNotes.enumerated() {
        var note = MIDINoteMessage(channel: 0, note: UInt8(noteNumber), velocity: 64, releaseVelocity: 0, duration: 1.0)
        MusicTrackNewMIDINoteEvent(track, Double(i), &note)
    }
    
    let config = SalieriConfiguration(staffSize: 8.0)
    let salieri = Salieri(configuration: config)
    let pdfDocument = salieri.renderPDF(from: sequence)
    
    // Save for inspection
    if let pdf = pdfDocument, let data = pdf.dataRepresentation() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("my_music_test.pdf")
        try? data.write(to: tempURL)
        print("My music test PDF saved to: \(tempURL.path)")
    }
}
```

### 2. Validate Output
- Open the generated PDF
- Check all items in the Visual Quality Checklist
- Compare with expected musical notation
- Note any issues for further development

## Configuration Recommendations

### For Standard Sheet Music
```swift
let config = SalieriConfiguration(
    pageSize: CGSize(width: 612, height: 792), // US Letter
    margins: EdgeInsets(top: 72, left: 72, bottom: 72, right: 72),
    staffSize: 8.0
)
```

### For Compact Layout
```swift
let config = SalieriConfiguration(
    pageSize: CGSize(width: 595, height: 842), // A4
    margins: EdgeInsets(top: 50, left: 50, bottom: 50, right: 50),
    staffSize: 6.0
)
```

### For Large Print
```swift
let config = SalieriConfiguration(
    pageSize: CGSize(width: 612, height: 792),
    margins: EdgeInsets(top: 100, left: 100, bottom: 100, right: 100),
    staffSize: 12.0
)
```

## Known Limitations

### Current Implementation
- ✅ Basic note rendering with stems
- ✅ Clef rendering (treble clef)
- ✅ Proper spacing and positioning
- ✅ Accidentals and ledger lines
- ✅ Staff wrapping and pagination
- ✅ Multi-track system breaking
- ⚠️ Time signatures (parsing issue -10855)
- ⚠️ Key signatures (basic support)
- ❌ Advanced beaming
- ❌ Slurs and ties
- ❌ Articulations

### Future Enhancements
- Fix time signature meta event parsing
- Add support for all clef types
- Implement advanced beaming rules
- Add slurs, ties, and articulations
- Support for text elements (dynamics, lyrics)
- Optimize system breaking algorithms
- Add page numbering and headers/footers

## Continuous Visual Testing

### Automated Checks
The visual tests run automatically with the test suite and verify:
- PDF generation succeeds
- File size is reasonable
- No crashes or errors

### Manual Validation
For critical releases, manually inspect generated PDFs:
1. Open each test PDF
2. Verify visual quality against checklist
3. Test with your specific MusicSequences
4. Document any issues found

This visual testing approach ensures that Salieri produces professional-quality sheet music output that meets your app's requirements. 