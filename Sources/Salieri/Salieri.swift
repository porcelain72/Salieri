import Foundation
import CoreGraphics
import CoreText
import PDFKit
import AudioToolbox

// MARK: - Cross-platform EdgeInsets
public struct EdgeInsets: Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

// MARK: - Salieri Public API

public struct SalieriConfiguration {
    public var pageSize: CGSize
    public var margins: EdgeInsets
    public var staffSize: CGFloat
    public var renderParts: Bool
    public var renderFullScore: Bool
    
    public init(pageSize: CGSize = CGSize(width: 595.2, height: 841.8), // A4 default
                margins: EdgeInsets = EdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                staffSize: CGFloat = 7.0,
                renderParts: Bool = false,
                renderFullScore: Bool = true) {
        self.pageSize = pageSize
        self.margins = margins
        self.staffSize = staffSize
        self.renderParts = renderParts
        self.renderFullScore = renderFullScore
    }
}

public class Salieri {
    public let configuration: SalieriConfiguration
    
    public init(configuration: SalieriConfiguration = SalieriConfiguration()) {
        self.configuration = configuration
        // Initialize SMuFL font
        SalieriSMuFLRenderer.initializeSMuFLFont()
    }
    
    /// Ingest a MusicSequence and return a PDF document
    public func renderPDF(from sequence: MusicSequence) -> PDFDocument? {
        // 1. Parse sequence into internal model
        let score = SalieriScore.from(sequence: sequence)
        // 2. Engrave (layout)
        let layout = SalieriEngraver.engrain(score: score, config: configuration)
        // 3. Render to PDF
        return SalieriPDFRenderer.render(layout: layout, config: configuration)
    }
    
    /// Ingest a MIDI file and return a PDF document
    public func renderPDF(fromMIDIFileAt url: URL) -> PDFDocument? {
        guard let sequence = SalieriMIDIParser.parseMIDIFile(at: url) else { return nil }
        return renderPDF(from: sequence)
    }
}

// MARK: - Internal Music Model (Expanded)

struct SalieriScore {
    var title: String?
    var parts: [SalieriPart]
    var isFullScore: Bool
    
    static func from(sequence: MusicSequence) -> SalieriScore {
        // 1. Extract tracks from MusicSequence
        var tracks: [MusicTrack] = []
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            if let t = track { tracks.append(t) }
        }
        
        // 2. For each track, create a SalieriPart
        let parts: [SalieriPart] = tracks.enumerated().map { (idx, track) in
            // TODO: Extract part name, instrument, etc.
            let measures = SalieriScore.parseMeasures(from: track)
            return SalieriPart(name: "Part \(idx+1)", measures: measures)
        }
        
        // 3. Return SalieriScore
        return SalieriScore(title: nil, parts: parts, isFullScore: true)
    }
    
    private static func parseMeasures(from track: MusicTrack) -> [SalieriMeasure] {
        var measures: [SalieriMeasure] = []
        var iterator: MusicEventIterator? = nil
        NewMusicEventIterator(track, &iterator)
        guard let eventIterator = iterator else { return measures }
        defer { DisposeMusicEventIterator(eventIterator) }
        
        var currentMeasureNumber = 1
        var currentEvents: [SalieriEvent] = []
        var currentTimeSignature = SalieriTimeSignature(numerator: 4, denominator: 4)
        var currentMeasureStartBeat: MusicTimeStamp = 0.0
        let beatsPerMeasure = { (ts: SalieriTimeSignature) in Double(ts.numerator) }
        
        var lastNoteEnd: MusicTimeStamp = 0.0
        var currentMeasureDuration: Double = 0.0 // Track cumulative duration in current measure
        
        var hasEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(eventIterator, &hasEvent)
        while hasEvent.boolValue {
            var timeStamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer? = nil
            var eventDataSize: UInt32 = 0
            MusicEventIteratorGetEventInfo(eventIterator, &timeStamp, &eventType, &eventData, &eventDataSize)
            
            // Detect rests (gap between last note end and this event's start)
            if timeStamp > lastNoteEnd {
                let restDuration = timeStamp - lastNoteEnd
                if restDuration > 0.0 {
                    let rest = SalieriRest(duration: .custom(restDuration))
                    currentEvents.append(.rest(rest))
                    currentMeasureDuration += restDuration
                }
            }
            
            // Map event to SalieriEvent
            if let event = mapEvent(eventType: eventType, eventData: eventData, timeStamp: timeStamp) {
                // Check if adding this event would exceed the measure's beat count
                let eventDuration: Double
                switch event {
                case .note(let note):
                    eventDuration = note.duration.fractionOfWhole
                case .rest(let rest):
                    eventDuration = rest.duration.fractionOfWhole
                default:
                    eventDuration = 0.0 // Time signatures, clefs, etc. don't consume beats
                }
                
                // If adding this event would exceed the measure, start a new measure
                if currentMeasureDuration + eventDuration > beatsPerMeasure(currentTimeSignature) {
                    measures.append(SalieriMeasure(number: currentMeasureNumber, events: currentEvents))
                    currentMeasureNumber += 1
                    currentEvents = []
                    currentMeasureDuration = 0.0
                    currentMeasureStartBeat += beatsPerMeasure(currentTimeSignature)
                }
                
                currentEvents.append(event)
                currentMeasureDuration += eventDuration
                
                // Update time signature if event is a time signature
                if case let .timeSignature(ts) = event {
                    currentTimeSignature = ts
                }
                
                // Track note end for rest detection
                if case let .note(note) = event {
                    lastNoteEnd = timeStamp + note.duration.fractionOfWhole
                }
            }
            
            MusicEventIteratorNextEvent(eventIterator)
            MusicEventIteratorHasCurrentEvent(eventIterator, &hasEvent)
        }
        
        if !currentEvents.isEmpty {
            measures.append(SalieriMeasure(number: currentMeasureNumber, events: currentEvents))
        }
        
        return measures
    }
    
    private static func mapEvent(eventType: MusicEventType, eventData: UnsafeRawPointer?, timeStamp: MusicTimeStamp) -> SalieriEvent? {
        // Map MIDI note events
        if eventType == kMusicEventType_MIDINoteMessage, let data = eventData?.assumingMemoryBound(to: MIDINoteMessage.self) {
            let midiNote = data.pointee
            let (step, octave, alter) = midiNoteToPitch(midiNote: midiNote.note)
            let duration = SalieriDuration.custom(Double(midiNote.duration))
            let accidental = alterToAccidental(alter)
            let note = SalieriNote(
                pitch: SalieriPitch(step: step, octave: octave, alter: alter),
                duration: duration,
                accidental: accidental,
                stemDirection: nil,
                beamType: nil,
                isChord: false
            )
            return .note(note)
        }
        // Map time signature meta events
        if eventType == kMusicEventType_Meta, let data = eventData?.assumingMemoryBound(to: MIDIMetaEvent.self) {
            let meta = data.pointee
            // Access tuple elements as a buffer of 32 bytes
            var metaData = [UInt8](repeating: 0, count: 32)
            withUnsafeBytes(of: meta.data) { rawBuf in
                for i in 0..<min(32, rawBuf.count) {
                    metaData[i] = rawBuf[i]
                }
            }
            if meta.metaEventType == 0x58, meta.dataLength >= 4 {
                let num = Int(metaData[0])
                let denom = Int(pow(2.0, Double(metaData[1])))
                let ts = SalieriTimeSignature(numerator: num, denominator: denom)
                return .timeSignature(ts)
            }
            if meta.metaEventType == 0x59, meta.dataLength >= 2 {
                let fifths = Int(Int8(bitPattern: metaData[0]))
                let mode = metaData[1] == 0 ? SalieriKeySignature.KeyMode.major : .minor
                let ks = SalieriKeySignature(fifths: fifths, mode: mode)
                return .keySignature(ks)
            }
        }
        // TODO: Map clef (not in MIDI, can infer or set default)
        // TODO: Extend for other event types (barlines, tuplets, etc.)
        return nil
    }
    
    // Helper: Convert MIDI note number to pitch (step, octave, alter)
    private static func midiNoteToPitch(midiNote: UInt8) -> (SalieriPitch.Step, Int, Double?) {
        let noteNames: [SalieriPitch.Step] = [.C, .C, .D, .D, .E, .F, .F, .G, .G, .A, .A, .B]
        let alters: [Double?] = [nil, 1.0, nil, 1.0, nil, nil, 1.0, nil, 1.0, nil, 1.0, nil]
        let noteIndex = Int(midiNote) % 12
        let octave = Int(midiNote) / 12 - 1
        let step = noteNames[noteIndex]
        let alter = alters[noteIndex]
        return (step, octave, alter)
    }
    // Helper: Convert alter to SalieriAccidental
    private static func alterToAccidental(_ alter: Double?) -> SalieriAccidental? {
        guard let a = alter else { return nil }
        switch a {
        case 1.0: return .sharp
        case -1.0: return .flat
        case 0.5: return .quarterSharp
        case -0.5: return .quarterFlat
        default: return .other("\(a)")
        }
    }
}

// Add fractionOfWhole computed property to SalieriDuration for rest detection
extension SalieriDuration {
    var fractionOfWhole: Double {
        switch self {
        case .whole: return 1.0
        case .half: return 0.5
        case .quarter: return 0.25
        case .eighth: return 0.125
        case .sixteenth: return 0.0625
        case .thirtySecond: return 0.03125
        case .sixtyFourth: return 0.015625
        case .dotted(let base, let dots):
            var value = base.fractionOfWhole
            for i in 0..<dots {
                value += base.fractionOfWhole / pow(2.0, Double(i+1))
            }
            return value
        case .custom(let v): return v
        }
    }
}

struct SalieriPart {
    var name: String?
    var measures: [SalieriMeasure]
    // Instrument, MIDI channel, etc. can be added here
}

struct SalieriMeasure {
    var number: Int
    var events: [SalieriEvent]
}

enum SalieriEvent {
    case note(SalieriNote)
    case rest(SalieriRest)
    case clef(SalieriClef)
    case keySignature(SalieriKeySignature)
    case timeSignature(SalieriTimeSignature)
    // Add more as needed (barlines, tuplets, etc.)
}

struct SalieriNote: Equatable {
    var pitch: SalieriPitch
    var duration: SalieriDuration
    var accidental: SalieriAccidental?
    var stemDirection: SalieriStemDirection?
    var beamType: SalieriBeamType?
    var isChord: Bool
    // Add articulations, ties, etc. as needed
}

struct SalieriRest: Equatable {
    var duration: SalieriDuration
}

struct SalieriClef {
    enum ClefType { case treble, bass, alto, tenor, percussion, other(String) }
    var type: ClefType
    var line: Int // Staff line (1=bottom)
}

struct SalieriKeySignature {
    var fifths: Int // Number of sharps (positive) or flats (negative)
    var mode: KeyMode
    enum KeyMode { case major, minor, other(String) }
}

struct SalieriTimeSignature {
    var numerator: Int
    var denominator: Int
}

// MARK: - Supporting Types

struct SalieriPitch: Equatable {
    var step: Step
    var octave: Int
    var alter: Double? // For microtonal (e.g., quarter-sharp = 0.5)
    
    enum Step: String, Equatable { case C, D, E, F, G, A, B }
}

enum SalieriAccidental: Equatable {
    case sharp, flat, natural, doubleSharp, doubleFlat
    case quarterSharp, quarterFlat, threeQuarterSharp, threeQuarterFlat
    case other(String) // For future microtonal support
}

indirect enum SalieriDuration: Equatable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth
    case dotted(base: SalieriDuration, dots: Int)
    case custom(Double) // Fraction of whole note
    
    static func ==(lhs: SalieriDuration, rhs: SalieriDuration) -> Bool {
        switch (lhs, rhs) {
        case (.whole, .whole), (.half, .half), (.quarter, .quarter), (.eighth, .eighth), (.sixteenth, .sixteenth), (.thirtySecond, .thirtySecond), (.sixtyFourth, .sixtyFourth): return true
        case let (.dotted(b1, d1), .dotted(b2, d2)): return b1 == b2 && d1 == d2
        case let (.custom(v1), .custom(v2)): return v1 == v2
        default: return false
        }
    }
}

enum SalieriStemDirection: Equatable { case up, down, unspecified }
enum SalieriBeamType: Equatable { case begin, continueBeam, end, none }

// MARK: - Engraving/Layout Model

struct SalieriLayout {
    var pages: [SalieriPage]
}

struct SalieriPage {
    var systems: [SalieriSystem]
    var pageNumber: Int
}

struct SalieriSystem {
    var staves: [SalieriStaff]
    var yPosition: CGFloat
    var systemNumber: Int
    var width: CGFloat
}

struct SalieriStaff {
    var measures: [SalieriMeasureLayout]
    var partName: String?
    var yPosition: CGFloat
    var staffNumber: Int
    var clef: SalieriClef // Assume one clef per staff for now
}

struct SalieriMeasureLayout {
    var events: [SalieriNotehead]
    var xPosition: CGFloat
    var width: CGFloat
    var measureNumber: Int
}

struct SalieriNotehead {
    var note: SalieriNote
    var x: CGFloat
    var y: CGFloat
    var accidental: SalieriAccidental?
    var ledgerLines: [LedgerLine]
    var stemDirection: SalieriStemDirection
    var beamGroup: Int?
    // Add more as needed (tie, slur, articulation, etc.)
}

struct LedgerLine {
    var y: CGFloat
    var length: CGFloat
}

// Add clef to staff for vertical positioning
// MARK: - Engraving Engine

class SalieriEngraver {
    static func engrain(score: SalieriScore, config: SalieriConfiguration) -> SalieriLayout {
        // Advanced engraving steps:
        // 1. System breaking: decide how many systems per page (paginate if needed)
        // 2. Staff layout: position staves within each system
        // 3. Measure layout: assign measures to systems, calculate widths
        // 4. Note layout: position noteheads, accidentals, stems, beams, ledger lines, etc.
        // 5. Pagination: split systems across pages
        
        let systemSpacing: CGFloat = 40.0 // Further reduced for professional density (4-6 systems per page)
        let staffSpacing: CGFloat = 35.0 // Further reduced for tighter multi-track spacing
        let staffLineSpacing: CGFloat = config.staffSize * 1.0 // Reduced spacing by one third
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        
        // Calculate available space for systems on each page
        let availableHeight = config.pageSize.height - config.margins.top - config.margins.bottom
        let availableWidth = config.pageSize.width - config.margins.left - config.margins.right
        
        // Calculate how many systems can fit on a page
        let systemHeight = CGFloat(score.parts.count) * staffSpacing + staffHeight
        let systemsPerPage = max(1, Int(availableHeight / (systemHeight + systemSpacing)))
        
        // Calculate measure widths based on content
        let measureWidths = calculateMeasureWidths(for: score, availableWidth: availableWidth, staffHeight: staffHeight, staffLineSpacing: staffLineSpacing)
        
        // Group measures into systems
        let systems = groupMeasuresIntoSystems(measureWidths: measureWidths, availableWidth: availableWidth)
        
        var pages: [SalieriPage] = []
        var currentPage = 1
        var currentSystem = 1
        
        // Group systems into pages
        let pagesOfSystems = stride(from: 0, to: systems.count, by: systemsPerPage).map { startIndex in
            let endIndex = min(startIndex + systemsPerPage, systems.count)
            return Array(systems[startIndex..<endIndex])
        }
        
        // Create pages with proper layout
        for (_, pageSystems) in pagesOfSystems.enumerated() {
            var pageSystemsList: [SalieriSystem] = []
            
            for (systemIndex, (measureStart, measureEnd, systemWidth)) in pageSystems.enumerated() {
                let systemYPosition = config.margins.top + CGFloat(systemIndex) * (systemHeight + systemSpacing)
                
                // Create staves for this system
                let staves: [SalieriStaff] = score.parts.enumerated().map { (partIdx, part) in
                    // Select appropriate clef based on note ranges in this part
                    let clef = selectClefForPart(part)
                    
                    // Get measures for this part in this system
                    let partMeasures: [SalieriMeasure]
                    if measureStart < part.measures.count {
                        let endIndex = min(measureEnd, part.measures.count)
                        partMeasures = Array(part.measures[measureStart..<endIndex])
                    } else {
                        partMeasures = []
                    }
                    
                    // Calculate stretched measure width for this system
                    let measuresInSystem = partMeasures.count
                    let stretchedMeasureWidth = systemWidth / CGFloat(measuresInSystem)
                    
                    let measures = partMeasures.enumerated().map { (index, measure) in
                        // Use stretched measure width for note positioning to ensure proper beat-based layout
                        // isFirstMeasure should be true for the first measure in each system (index == 0)
                        let measureLayout = createMeasureLayout(measure, localMeasureIndex: index, measureWidth: stretchedMeasureWidth, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight, clef: clef, isFirstMeasure: index == 0)
                        
                        let xPosition = CGFloat(index) * stretchedMeasureWidth
                        let positionedMeasure = SalieriMeasureLayout(events: measureLayout.events, xPosition: xPosition, width: stretchedMeasureWidth, measureNumber: measureLayout.measureNumber)
                        return positionedMeasure
                    }
                    
                    let staffYPosition = systemYPosition + CGFloat(partIdx) * staffSpacing
                    return SalieriStaff(measures: measures, partName: part.name, yPosition: staffYPosition, staffNumber: partIdx + 1, clef: clef)
                }
                
                let system = SalieriSystem(staves: staves, yPosition: systemYPosition, systemNumber: currentSystem, width: systemWidth)
                pageSystemsList.append(system)
                currentSystem += 1
            }
            
            let page = SalieriPage(systems: pageSystemsList, pageNumber: currentPage)
            pages.append(page)
            currentPage += 1
        }
        
        return SalieriLayout(pages: pages)
    }
    
    // Helper: Calculate measure widths using the new algorithm
    private static func calculateMeasureWidths(for score: SalieriScore, availableWidth: CGFloat, staffHeight: CGFloat, staffLineSpacing: CGFloat) -> [CGFloat] {
        let maxMeasures = score.parts.map { $0.measures.count }.max() ?? 0
        var measureWidths: [CGFloat] = []
        
        // Space needed for clef, time signature, and key signature in first measure
        // Use staffLineSpacing for consistent sizing with SMuFL standards
        let clefWidth = staffLineSpacing * 3.0 // Clef width = 3 staff spaces
        let timeSignatureWidth = staffLineSpacing * 2.0 * 2 // Time signature width (numerator + denominator) = 2 staff spaces each
        let keySignatureWidth = staffLineSpacing * 0.0 // No key signature for now
        let signatureSpacing = staffLineSpacing * 1.0 // Spacing after signatures
        let firstMeasureExtraWidth = clefWidth + timeSignatureWidth + keySignatureWidth + signatureSpacing
        
        // Calculate notehead minimum size from staffLineSpacing
        let noteheadMinSize = staffLineSpacing * 0.6 // Base notehead width (SMuFL standard: ~0.6 staff spaces)
        let minNoteSpacing = staffHeight * 0.5
        
        // Calculate a reasonable minimum measure width based on typical note density
        // Use 4 notes as a reasonable minimum (4/4 time signature with quarter notes)
        let typicalNotesPerMeasure = 4
        let minMeasureWidth = CGFloat(typicalNotesPerMeasure) * noteheadMinSize + CGFloat(typicalNotesPerMeasure + 1) * minNoteSpacing
        
        // Calculate available width for measures (system width minus space for clefs/signatures)
        let availableMeasureWidth = availableWidth - firstMeasureExtraWidth
        
        // Determine how many measures can fit in a system
        let measuresPerSystem = max(1, Int(availableMeasureWidth / minMeasureWidth))
        
        // Debug output
        print("Measure width calculation debug:")
        print("  typicalNotesPerMeasure: \(typicalNotesPerMeasure)")
        print("  noteheadMinSize: \(noteheadMinSize)")
        print("  minNoteSpacing: \(minNoteSpacing)")
        print("  minMeasureWidth: \(minMeasureWidth)")
        print("  availableWidth: \(availableWidth)")
        print("  firstMeasureExtraWidth: \(firstMeasureExtraWidth)")
        print("  availableMeasureWidth: \(availableMeasureWidth)")
        print("  measuresPerSystem: \(measuresPerSystem)")
        
        // Calculate base measure width by dividing available space by number of measures
        let baseMeasureWidth = availableMeasureWidth / CGFloat(measuresPerSystem)
        
        // Generate measure widths
        for measureIndex in 0..<maxMeasures {
            if measureIndex == 0 {
                // First measure includes space for clefs and signatures
                measureWidths.append(baseMeasureWidth + firstMeasureExtraWidth)
            } else {
                // Regular measures
                measureWidths.append(baseMeasureWidth)
            }
        }
        
        return measureWidths
    }
    
    // Helper: Group measures into systems
    private static func groupMeasuresIntoSystems(measureWidths: [CGFloat], availableWidth: CGFloat) -> [(startIndex: Int, endIndex: Int, systemWidth: CGFloat)] {
        var systems: [(startIndex: Int, endIndex: Int, systemWidth: CGFloat)] = []
        var currentMeasure = 0
        
        while currentMeasure < measureWidths.count {
            var systemWidth: CGFloat = 0
            var measuresInSystem = 0
            
            // Try to fit as many complete measures as possible in this system
            while currentMeasure + measuresInSystem < measureWidths.count {
                let nextMeasureWidth = measureWidths[currentMeasure + measuresInSystem]
                
                // Check if adding this measure would exceed available width
                if systemWidth + nextMeasureWidth <= availableWidth {
                    systemWidth += nextMeasureWidth
                    measuresInSystem += 1
                } else {
                    // If we can't fit this measure, stop here
                    // Don't break measures - ensure systems contain whole measures only
                    break
                }
            }
            
            // If we couldn't fit any measures in this system, force at least one
            // This handles the case where a single measure is wider than the available width
            if measuresInSystem == 0 {
                measuresInSystem = 1
                systemWidth = measureWidths[currentMeasure]
            }
            
            // Stretch measures to fill the available width evenly
            // This ensures systems look balanced and professional
            let stretchedSystemWidth = availableWidth
            systems.append((startIndex: currentMeasure, endIndex: currentMeasure + measuresInSystem, systemWidth: stretchedSystemWidth))
            currentMeasure += measuresInSystem
        }
        
        return systems
    }
    
    // Helper: Select appropriate clef based on note ranges in a part
    private static func selectClefForPart(_ part: SalieriPart) -> SalieriClef {
        // Collect all notes from the part
        let allNotes = part.measures.flatMap { measure in
            measure.events.compactMap { event in
                if case let .note(note) = event {
                    return note
                }
                return nil
            }
        }
        
        guard !allNotes.isEmpty else {
            return SalieriClef(type: .treble, line: 2) // Default to treble
        }
        
        // Calculate average MIDI note number
        let midiNumbers = allNotes.map { midiNumberForPitch($0.pitch) }
        let averageMidi = midiNumbers.reduce(0, +) / midiNumbers.count
        
        // Select clef based on average pitch
        if averageMidi < 50 { // Below C3
            return SalieriClef(type: .bass, line: 4)
        } else if averageMidi < 60 { // C3 to C4
            return SalieriClef(type: .bass, line: 4)
        } else { // C4 and above
            return SalieriClef(type: .treble, line: 2)
        }
    }
    
    // Helper: Create measure layout with proper note positioning
    private static func createMeasureLayout(_ measure: SalieriMeasure, localMeasureIndex: Int, measureWidth: CGFloat, staffLineSpacing: CGFloat, staffHeight: CGFloat, clef: SalieriClef, isFirstMeasure: Bool = false) -> SalieriMeasureLayout {
        let notesPerBeamGroup = 2
        var beamGroup = 0
        var beamCount = 0
        
        let events: [SalieriNotehead] = measure.events.enumerated().compactMap { (eIdx, event) in
            if case let .note(note) = event {
                // Assign beam group
                var group: Int? = nil
                if note.duration == .eighth || note.duration == .sixteenth {
                    group = beamGroup
                    beamCount += 1
                    if beamCount >= notesPerBeamGroup {
                        beamGroup += 1
                        beamCount = 0
                    }
                }
                
                // Calculate vertical position (y) based on pitch and clef
                let y = yForPitch(note.pitch, clef: clef, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight)
                
                // Accidentals
                let accidental = note.accidental
                
                // Ledger lines
                let ledgerLines = ledgerLinesForPitch(note.pitch, clef: clef, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight)
                
                // Stem direction (up for notes below middle line, down for above)
                let stemDirection: SalieriStemDirection = y > staffHeight / 2 ? .up : .down
                
                // Calculate horizontal position within the measure
                let xPosition = calculateNotePosition(for: note, measureIndex: eIdx, measureWidth: measureWidth, totalNotes: measure.events.count, isFirstMeasure: isFirstMeasure, staffHeight: staffHeight, staffLineSpacing: staffLineSpacing)
                
                return SalieriNotehead(note: note, x: xPosition, y: y, accidental: accidental, ledgerLines: ledgerLines, stemDirection: stemDirection, beamGroup: group)
            }
            return nil
        }
        
        return SalieriMeasureLayout(events: events, xPosition: 0, width: measureWidth, measureNumber: measure.number)
    }
    
    // Helper: Calculate note position within a measure using n notes and n+1 spaces
    private static func calculateNotePosition(for note: SalieriNote, measureIndex: Int, measureWidth: CGFloat, totalNotes: Int, isFirstMeasure: Bool = false, staffHeight: CGFloat, staffLineSpacing: CGFloat) -> CGFloat {
        // Calculate space needed for clef, time signature, and key signature
        // Use staffLineSpacing for consistency with SMuFL standards
        let clefWidth = staffLineSpacing * 3.0 // Clef width = 3 staff spaces
        let timeSignatureWidth = staffLineSpacing * 2.0 * 2 // Time signature width (numerator + denominator) = 2 staff spaces each
        let keySignatureWidth = staffLineSpacing * 0.0 // No key signature for now
        let signatureSpacing = staffLineSpacing * 1.0 // Spacing after signatures
        let signatureSpace = clefWidth + timeSignatureWidth + keySignatureWidth + signatureSpacing
        
        // Calculate available width for notes (measure width minus signature space if first measure)
        let availableNoteWidth = isFirstMeasure ? measureWidth - signatureSpace : measureWidth
        
        // Calculate note width and spacing
        let noteWidth = staffLineSpacing * 0.6 // Note width (SMuFL standard)
        let noteSpacing = staffHeight * 0.5 // Space between notes
        
        // Calculate total space needed: n notes + (n+1) spaces
        let totalNoteWidth = CGFloat(totalNotes) * noteWidth
        let totalSpacingWidth = CGFloat(totalNotes + 1) * noteSpacing
        let totalRequiredWidth = totalNoteWidth + totalSpacingWidth
        
        // If total required width exceeds available width, scale down the spacing
        let actualSpacing = totalRequiredWidth > availableNoteWidth ? 
            (availableNoteWidth - totalNoteWidth) / CGFloat(totalNotes + 1) : noteSpacing
        
        // Calculate starting position
        var startPosition: CGFloat = 0
        
        // If this is the first measure, start after the signature space
        if isFirstMeasure {
            startPosition = signatureSpace
        }
        
        // Add initial space
        startPosition += actualSpacing
        
        // Add space for previous notes and their spacing
        startPosition += CGFloat(measureIndex) * (noteWidth + actualSpacing)
        
        // Debug output for note positioning
        if measureIndex == 0 {
            print("Note positioning debug for first note in measure:")
            print("  isFirstMeasure: \(isFirstMeasure)")
            print("  measureWidth: \(measureWidth)")
            print("  signatureSpace: \(signatureSpace)")
            print("  availableNoteWidth: \(availableNoteWidth)")
            print("  totalNotes: \(totalNotes)")
            print("  noteWidth: \(noteWidth)")
            print("  noteSpacing: \(noteSpacing)")
            print("  totalRequiredWidth: \(totalRequiredWidth)")
            print("  actualSpacing: \(actualSpacing)")
            print("  startPosition: \(startPosition)")
        }
        
        return startPosition
    }
    
    // Helper: Calculate note width based on duration
    private static func calculateNoteWidth(for note: SalieriNote, staffHeight: CGFloat) -> CGFloat {
        let staffLineSpacing = staffHeight / 4.0 // Convert staff height back to line spacing
        // SMuFL specification: noteheads are approximately 0.6 staff spaces wide
        let baseWidth = staffLineSpacing * 0.6 // Note head width (SMuFL standard)
        let durationMultiplier: CGFloat
        switch note.duration {
        case .whole: durationMultiplier = 1.0
        case .half: durationMultiplier = 1.0
        case .quarter: durationMultiplier = 1.0
        case .eighth: durationMultiplier = 1.0
        case .sixteenth: durationMultiplier = 1.0
        case .thirtySecond: durationMultiplier = 1.0
        case .sixtyFourth: durationMultiplier = 1.0
        case .dotted(_, _): durationMultiplier = 1.2 // Slightly wider for dots
        case .custom(_): durationMultiplier = 1.0
        }
        return baseWidth * durationMultiplier
    }
    
    // Helper: Calculate vertical position for a pitch on the staff
    // Y position is relative to the bottom of the staff (yBase)
    // For notes below the staff, we ADD to yBase
    // For notes above the staff, we SUBTRACT from yBase
    private static func yForPitch(_ pitch: SalieriPitch, clef: SalieriClef, staffLineSpacing: CGFloat, staffHeight: CGFloat) -> CGFloat {
        let midiNumber = midiNumberForPitch(pitch)
        
        // Calculate the bottom line Y position for comparison
        let bottomLineY = staffHeight // / 2 // Bottom line is at the center of the staff
        
        let noteY: CGFloat
        switch clef.type {
        case .treble:
            noteY = yForPitchTreble(midiNumber: midiNumber, staffLineSpacing: staffLineSpacing)
        case .bass:
            noteY = yForPitchBass(midiNumber: midiNumber, staffLineSpacing: staffLineSpacing)
        default:
            // For other clef types, use a simple calculation
            let c4 = 60
            let offset = midiNumber - c4
            noteY = CGFloat(offset) * (staffLineSpacing / 2)
        }
        
        // Debug: Compare note Y position with bottom line position
        print("Note Y position debug:")
        print("  MIDI number: \(midiNumber)")
        print("  staffHeight: \(staffHeight)")
        print("  bottomLineY: \(bottomLineY)")
        print("  noteY (relative): \(noteY)")
        print("  final note Y (bottomLineY + noteY): \(bottomLineY + noteY)")
        
        // Return only the relative offset - the rendering code will add yBase
        return noteY
    }
    
    // Treble clef lookup table: MIDI number -> staff position offset
    // E4 (MIDI 64) is on the bottom line (y = 0)
    // For notes below E4, we ADD to yBase (positive values)
    // For notes above E4, we SUBTRACT from yBase (negative values)
    private static func yForPitchTreble(midiNumber: Int, staffLineSpacing: CGFloat) -> CGFloat {
        // Debug output for Y position calculation
        print("Y position calculation debug:")
        print("  MIDI number: \(midiNumber)")
        print("  staffLineSpacing: \(staffLineSpacing)")
        
        let trebleLookup: [Int: CGFloat] = [
            // Below staff (ledger lines below)
            60: 1.0,   // C4 - one ledger lines below
            61: 1.0,   // C#4 - one  ledger lines below
            62: 0.5,   // D4 - half ledger line below
            63: 0.5,   // D#4 - half ledger line below
            
            // Staff lines and spaces (bottom to top)
            64: 0.0,   // E4 - bottom line
            65: -0.5,  // F4 - bottom space
            66: -0.5,  // F#4 - bottom space
            67: -1.0,  // G4 - second line
            68: -1.0,  // G#4 - second line
            69: -1.5,  // A4 - second space
            70: -1.5,  // A#4 - second space
            71: -2.0,  // B4 - third line
            72: -2.5,  // C5 - fourth space
            73: -2.5,  // C#5 - fourth space
            74: -3.0,  // D5 - fourth line
            75: -3.0,  // D#5 - fourth line
            76: -3.5,  // E5 - fourth space
            77: -4.0,  // F5 - fourth space
            78: -4.0,  // F#5 -  top line
            79: -4.5,  // G5 - above top line
            80: -4.5,  // G#5 - above top line
            81: -5.0,  // A5 - above top line
            82: -5.0,  // A#5 - above top line
            83: -5.5,  // B5 - above top line
            84: -6.0, // C6 - above top line
        ]
        
        if let multiplier = trebleLookup[midiNumber] {
            let result = multiplier * staffLineSpacing
            print("  lookup multiplier: \(multiplier)")
            print("  calculated Y: \(result)")
            return result
        } else {
            // For notes outside the lookup table, calculate based on distance from E4
            let e4 = 64
            let offset = midiNumber - e4
            let result = CGFloat(offset) * (staffLineSpacing / 2)
            print("  fallback calculation: offset=\(offset), result=\(result)")
            return result
        }
    }
    
    // Bass clef lookup table: MIDI number -> staff position offset
    // F3 (MIDI 53) is on the bottom line (y = 0)
    // For notes below F3, we ADD to yBase (positive values)
    // For notes above F3, we SUBTRACT from yBase (negative values)
    private static func yForPitchBass(midiNumber: Int, staffLineSpacing: CGFloat) -> CGFloat {
        let bassLookup: [Int: CGFloat] = [
            // Below staff (ledger lines below)
            50: 1.5,   // D3 - one ledger line below
            51: 1.0,   // D#3 - half space below
            52: 0.5,   // E3 - half space below
            
            // Staff lines and spaces (bottom to top)
            53: 0.0,   // F3 - bottom line
            54: -0.5,  // F#3 - bottom space
            55: -1.0,  // G3 - first line
            56: -1.5,  // G#3 - first space
            57: -2.0,  // A3 - second line
            58: -2.5,  // A#3 - second space
            59: -3.0,  // B3 - third line
            60: -3.5,  // C4 - third space
            61: -4.0,  // C#4 - fourth line
            62: -4.5,  // D4 - fourth space
            63: -5.0,  // D#4 - top line
            64: -5.5,  // E4 - above top line
            65: -6.0,  // F4 - above top line
            66: -6.5,  // F#4 - above top line
            67: -7.0,  // G4 - above top line
            68: -7.5,  // G#4 - above top line
            69: -8.0,  // A4 - above top line
            70: -8.5,  // A#4 - above top line
            71: -9.0,  // B4 - above top line
            72: -9.5,  // C5 - above top line
        ]
        
        if let multiplier = bassLookup[midiNumber] {
            return multiplier * staffLineSpacing
        } else {
            // For notes outside the lookup table, calculate based on distance from F3
            let f3 = 53
            let offset = midiNumber - f3
            return CGFloat(offset) * (staffLineSpacing / 2)
        }
    }
    // Helper: Calculate ledger lines for a pitch
    private static func ledgerLinesForPitch(_ pitch: SalieriPitch, clef: SalieriClef, staffLineSpacing: CGFloat, staffHeight: CGFloat) -> [LedgerLine] {
        // Calculate the actual Y position of the note on the staff
        let noteY = yForPitch(pitch, clef: clef, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight)
        
        var lines: [LedgerLine] = []
        
        // For treble clef: D4 (bottom line) to G5 (top line) don't need ledger lines
        // D4 = MIDI 62, G5 = MIDI 79
        let midiNumber = midiNumberForPitch(pitch)
        
        switch clef.type {
        case .treble:
            if midiNumber < 62 { // Below D4 (below bottom line)
                // Calculate how many ledger lines are needed below the staff
                let bottomLineY = 0.0 // Bottom line of staff
                let distanceBelow = bottomLineY - noteY
                let ledgerCount = max(0, Int(ceil(distanceBelow / staffLineSpacing)))
                
                for i in 0..<ledgerCount {
                    let ledgerLineY = bottomLineY - CGFloat(i + 1) * staffLineSpacing
                    lines.append(LedgerLine(y: ledgerLineY, length: staffLineSpacing * 1.5))
                }
            } else if midiNumber > 79 { // Above G5 (above top line)
                // Calculate how many ledger lines are needed above the staff
                // For treble clef: G5 (MIDI 79) is the top line, so notes above need ledger lines
                // A5 (MIDI 81) should have 1 ledger line, B5 (MIDI 83) should have 2 ledger lines
                let semitonesAboveG5 = midiNumber - 79
                let ledgerCount = (semitonesAboveG5 + 1) / 2 // Convert semitones to ledger lines
                
                for i in 0..<ledgerCount {
                    let ledgerLineY = staffHeight + CGFloat(i + 1) * staffLineSpacing
                    lines.append(LedgerLine(y: ledgerLineY, length: staffLineSpacing * 1.5))
                }
            }
            // Notes from D4 (62) to G5 (79) are within the staff and don't need ledger lines
            
        case .bass:
            // For bass clef: F3 (bottom line) to A4 (top line) don't need ledger lines
            // F3 = MIDI 53, A4 = MIDI 69
            if midiNumber < 53 { // Below F3 (below bottom line)
                let bottomLineY = 0.0
                let distanceBelow = bottomLineY - noteY
                let ledgerCount = max(0, Int(ceil(distanceBelow / staffLineSpacing)))
                
                for i in 0..<ledgerCount {
                    let ledgerLineY = bottomLineY - CGFloat(i + 1) * staffLineSpacing
                    lines.append(LedgerLine(y: ledgerLineY, length: staffLineSpacing * 1.5))
                }
            } else if midiNumber > 69 { // Above A4 (above top line)
                let topLineY = staffHeight
                let distanceAbove = noteY - topLineY
                let ledgerCount = max(0, Int(ceil(distanceAbove / staffLineSpacing)))
                
                for i in 0..<ledgerCount {
                    let ledgerLineY = topLineY + CGFloat(i + 1) * staffLineSpacing
                    lines.append(LedgerLine(y: ledgerLineY, length: staffLineSpacing * 1.5))
                }
            }
            // Notes from F3 (53) to A4 (69) are within the staff and don't need ledger lines
            
        default:
            // For other clef types, use a simple range check
            if noteY < 0 || noteY > staffHeight {
                // Calculate ledger lines based on actual position
                if noteY < 0 { // Above staff
                    let ledgerCount = max(0, Int(ceil(abs(noteY) / staffLineSpacing)))
                    for i in 0..<ledgerCount {
                        let ledgerLineY = -CGFloat(i + 1) * staffLineSpacing
                        lines.append(LedgerLine(y: ledgerLineY, length: staffLineSpacing * 1.5))
                    }
                } else { // Below staff
                    let ledgerCount = max(0, Int(ceil((noteY - staffHeight) / staffLineSpacing)))
                    for i in 0..<ledgerCount {
                        let ledgerLineY = staffHeight + CGFloat(i + 1) * staffLineSpacing
                        lines.append(LedgerLine(y: ledgerLineY, length: staffLineSpacing * 1.5))
                    }
                }
            }
        }
        
        return lines
    }
    // Helper: MIDI number for pitch
    private static func midiNumberForPitch(_ pitch: SalieriPitch) -> Int {
        let stepToInt: [SalieriPitch.Step: Int] = [.C: 0, .D: 2, .E: 4, .F: 5, .G: 7, .A: 9, .B: 11]
        let base = (pitch.octave + 1) * 12
        let step = stepToInt[pitch.step] ?? 0
        let alter = Int((pitch.alter ?? 0).rounded())
        return base + step + alter
    }
    
    // Helper: Calculate semitone offset from Middle C (C4)
    private static func semitoneOffsetFromC4(_ pitch: SalieriPitch) -> Int {
        return midiNumberForPitch(pitch) - 60 // C4 = MIDI 60
    }
}

// MARK: - PDF Rendering

class SalieriPDFRenderer {
    static func render(layout: SalieriLayout, config: SalieriConfiguration) -> PDFDocument? {
        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
        var mediaBox = CGRect(origin: .zero, size: config.pageSize)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        for page in layout.pages {
            pdfContext.beginPage(mediaBox: &mediaBox)
            // Flip context for correct orientation
            pdfContext.saveGState()
            pdfContext.translateBy(x: 0, y: config.pageSize.height)
            pdfContext.scaleBy(x: 1, y: -1)
            // Draw page margin
            drawPageMargin(context: pdfContext, rect: mediaBox, margins: config.margins)
            // Draw each system
            for system in page.systems {
                drawSystem(system, context: pdfContext, config: config)
            }
            pdfContext.restoreGState()
            pdfContext.endPage()
        }
        pdfContext.closePDF()
        return PDFDocument(data: pdfData as Data)
    }
    
    private static func drawPageMargin(context: CGContext, rect: CGRect, margins: EdgeInsets) {
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.setLineWidth(1.0)
        let marginRect = CGRect(x: margins.left, y: margins.bottom, width: rect.width - margins.left - margins.right, height: rect.height - margins.top - margins.bottom)
        context.stroke(marginRect)
    }
    
    private static func drawSystem(_ system: SalieriSystem, context: CGContext, config: SalieriConfiguration) {
        for staff in system.staves {
            drawStaff(staff, systemWidth: system.width, context: context, config: config)
        }
    }
    
    private static func drawStaff(_ staff: SalieriStaff, systemWidth: CGFloat, context: CGContext, config: SalieriConfiguration) {
        let staffLineSpacing: CGFloat = config.staffSize * 1.0 // Reduced spacing by one third
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        let yBase = staff.yPosition
        
        // Draw staff lines across full page width
        context.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
        context.setLineWidth(1.0)
        for i in 0..<staffLines {
            let y = yBase + CGFloat(i) * staffLineSpacing
            context.move(to: CGPoint(x: config.margins.left, y: y)) // Start at left margin
            context.addLine(to: CGPoint(x: config.pageSize.width - config.margins.right, y: y)) // End at right margin
        }
        context.strokePath()
        
        // Draw clef and time signature within the first measure
        if let firstMeasure = staff.measures.first {
            let firstMeasureX = config.margins.left + firstMeasure.xPosition
            
            // Position clef and time signature to match the calculated gap (96.0pt)
            let clefX = firstMeasureX + staffLineSpacing * 1.0 // 1 staff space from measure start
            let clefY = yBase + staffHeight / 2 // Center clef vertically on staff
            drawClef(staff.clef, at: CGPoint(x: clefX, y: clefY), context: context, config: config)
            
            // Draw time signature after clef (clef width = 3 staff spaces)
            let timeSigX = clefX + staffLineSpacing * 3.0 // Position after clef width
            let timeSigY = yBase + staffHeight / 2
            drawTimeSignature(firstMeasure, at: CGPoint(x: timeSigX, y: timeSigY), context: context, config: config)
        }
        
        // Draw measures
        for measure in staff.measures {
            drawMeasure(measure, yBase: yBase, context: context, config: config)
        }
    }
    
    private static func drawClef(_ clef: SalieriClef, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        // Use SMuFL font renderer with fallback to SVG
        SalieriSMuFLRenderer.drawSMuFLClef(clef, at: point, context: context, config: config)
    }
    
    private static func drawTimeSignature(_ measure: SalieriMeasureLayout, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        // Calculate staff height for proper scaling
        let staffLineSpacing: CGFloat = config.staffSize * 1.0
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        
        // SMuFL specification: time signature digits should be 2 staff spaces tall (0.5 em)
        let timeSignatureSize = staffLineSpacing * 2.0 // Time signature height = 2 staff spaces
        
        // Draw "4" for numerator - adjust Y position to center the symbol
        let numeratorPoint = CGPoint(x: point.x, y: point.y - staffHeight * 0.25 + timeSignatureSize * 0.5)
        SalieriSMuFLRenderer.drawSMuFLSymbol("time_signature_4", at: numeratorPoint, context: context, config: config, size: timeSignatureSize)
        
        // Draw "4" for denominator - adjust Y position to center the symbol
        let denominatorPoint = CGPoint(x: point.x, y: point.y + staffHeight * 0.25 + timeSignatureSize * 0.5)
        SalieriSMuFLRenderer.drawSMuFLSymbol("time_signature_4", at: denominatorPoint, context: context, config: config, size: timeSignatureSize)
    }
    
    private static func drawMeasure(_ measure: SalieriMeasureLayout, yBase: CGFloat, context: CGContext, config: SalieriConfiguration) {
        // Draw measure line at start
        let xStart = config.margins.left + measure.xPosition // Start from left margin
        let xEnd = xStart + measure.width
        let staffLineSpacing: CGFloat = config.staffSize * 1.0
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        
        context.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: xStart, y: yBase))
        context.addLine(to: CGPoint(x: xStart, y: yBase + staffHeight))
        context.strokePath()
        
        // Draw notes using their calculated positions within the measure
        for notehead in measure.events {
            let noteX = xStart + notehead.x // Use the calculated x position
            drawNotehead(notehead, xBase: noteX, yBase: yBase, context: context, config: config)
        }
        
        // Draw measure line at end
        context.move(to: CGPoint(x: xEnd, y: yBase))
        context.addLine(to: CGPoint(x: xEnd, y: yBase + staffHeight))
        context.strokePath()
    }
    
    private static func drawNotehead(_ notehead: SalieriNotehead, xBase: CGFloat, yBase: CGFloat, context: CGContext, config: SalieriConfiguration) {
        let x = xBase
      //  let y = yBase// + notehead.y
      //  let y =  notehead.y
        let y = yBase + notehead.y
        // Debug: Check rendering Y position calculation
        print("Rendering Y position debug:")
        print("  yBase: \(yBase)")
        print("  notehead.y (relative): \(notehead.y)")
        print("  final rendering Y: \(y)")
        
        // Calculate staff height for proper scaling
        let staffLineSpacing: CGFloat = config.staffSize * 1.0
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        
        // Draw SMuFL note
        SalieriSMuFLRenderer.drawSMuFLNote(notehead, at: CGPoint(x: x, y: y), context: context, config: config)
        
        // Calculate note radius based on staff height
        let noteRadius = staffHeight * 0.2 // Note radius should be about 20% of staff height
        

        
        // Draw SMuFL accidental with proper positioning
        if let accidental = notehead.accidental {
            let accidentalPoint = CGPoint(x: x - noteRadius * 2.5, y: y - noteRadius * 0.5)
            SalieriSMuFLRenderer.drawSMuFLAccidental(accidental, at: accidentalPoint, context: context, config: config)
        }
        
        // Draw SMuFL ledger lines
        for ledger in notehead.ledgerLines {
            let ledgerPoint = CGPoint(x: x, y: yBase + ledger.y)
            let ledgerSize = noteRadius * 3.0 // Ledger lines should be about 3x note radius
            SalieriSMuFLRenderer.drawSMuFLSymbol("ledger_line", at: ledgerPoint, context: context, config: config, size: ledgerSize)
        }
    }
    

}

// MARK: - SMuFL Font Renderer

class SalieriSMuFLRenderer {
    private static var smuflFont: CGFont?
    private static let fontCache = NSCache<NSString, CGPath>()
    
    /// Initialize SMuFL font
    static func initializeSMuFLFont() {
        // Load SMuFL font from bundle
        if let fontURL = Bundle.module.url(forResource: "Bravura", withExtension: "otf"),
           let fontData = try? Data(contentsOf: fontURL),
           let provider = CGDataProvider(data: fontData as CFData),
           let font = CGFont(provider) {
            
            // Register the font with the system
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterGraphicsFont(font, &error) {
                print("Failed to register font: \(error?.takeRetainedValue().localizedDescription ?? "unknown error")")
            } else {
                print("Font registered successfully")
            }
            
            smuflFont = font
            print("SMuFL font loaded successfully")
        } else {
            print("Warning: SMuFL font not found, falling back to SVG rendering")
        }
    }
    
    /// Get SMuFL Unicode for musical symbol
    private static func smuflUnicode(for symbol: String) -> UniChar? {
        let smuflMap: [String: UniChar] = [
            // Clefs
            "treble_clef": 0xE050,
            "bass_clef": 0xE062,
            "alto_clef": 0xE05C,
            "tenor_clef": 0xE05D,
            "percussion_clef": 0xE069,
            
            // Notes
            "whole_note": 0xE1D2,
            "half_note": 0xE1D3,
            "quarter_note": 0xE1D5,
            "eighth_note": 0xE1D7,
            "sixteenth_note": 0xE1D9,
            "thirty_second_note": 0xE1DB,
            "sixty_fourth_note": 0xE1DD,
            
            // Rests
            "whole_rest": 0xE4E3,
            "half_rest": 0xE4E4,
            "quarter_rest": 0xE4E5,
            "eighth_rest": 0xE4E6,
            "sixteenth_rest": 0xE4E7,
            "thirty_second_rest": 0xE4E8,
            "sixty_fourth_rest": 0xE4E9,
            
            // Accidentals
            "sharp": 0xE262,
            "flat": 0xE260,
            "natural": 0xE261,
            "double_sharp": 0xE263,
            "double_flat": 0xE264,
            "quarter_sharp": 0xE280,
            "quarter_flat": 0xE281,
            "three_quarter_sharp": 0xE282,
            "three_quarter_flat": 0xE283,
            
            // Time signatures
            "time_signature_0": 0xE080,
            "time_signature_1": 0xE081,
            "time_signature_2": 0xE082,
            "time_signature_3": 0xE083,
            "time_signature_4": 0xE084,
            "time_signature_5": 0xE085,
            "time_signature_6": 0xE086,
            "time_signature_7": 0xE087,
            "time_signature_8": 0xE088,
            "time_signature_9": 0xE089,
            "time_signature_common": 0xE08A,
            "time_signature_cut": 0xE08B,
            
            // Stems and beams
            "stem": 0xE210,
            "beam": 0xE1E0,
            
            // Ledger lines
            "ledger_line": 0xE022,
            
            // Bar lines
            "barline_single": 0xE030,
            "barline_double": 0xE031,
            "barline_final": 0xE032,
            "barline_repeat_start": 0xE040,
            "barline_repeat_end": 0xE041
        ]
        
        return smuflMap[symbol]
    }
    
    /// Draw SMuFL symbol at specified position
    static func drawSMuFLSymbol(_ symbol: String, at point: CGPoint, context: CGContext, config: SalieriConfiguration, size: CGFloat? = nil) {
        guard let unicode = smuflUnicode(for: symbol),
              let font = smuflFont else {
            // Fallback to simple line drawing if SMuFL symbol not found
            drawFallbackSymbol(symbol, at: point, context: context, config: config)
            return
        }
        
        let symbolSize = size ?? config.staffSize * 2.0
        
        // Create attributed string with SMuFL font
        let unicodeScalar = UnicodeScalar(unicode)!
        let string = String(unicodeScalar)
        

        
        // Try using the CGFont directly with Core Text

        
        // Also try with a different approach - use the font name
        let fontName = font.postScriptName as String? ?? "Bravura"
        let fontDescriptor = CTFontDescriptorCreateWithNameAndSize(fontName as CFString, symbolSize)
        let ctFontByName = CTFontCreateWithFontDescriptor(fontDescriptor, 0, nil)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ctFontByName, // Try using the font by name instead
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        
        // Draw the symbol using Core Text
        // SMuFL specification: glyphs are registered with specific baseline positions
        let isNote = symbol.contains("note") || symbol.contains("rest")
        let isAccidental = symbol.contains("sharp") || symbol.contains("flat") || symbol.contains("natural")
        let isClef = symbol.contains("clef")
        
        let yOffset: CGFloat
        if isNote {
            // SMuFL: Noteheads positioned as if on bottom line of staff
            // The notehead center should be at the staff line position
            // In SMuFL, noteheads are vertically centered on baseline (y=0)
            yOffset = symbolSize / 2
        } else if isAccidental {
            // SMuFL: Accidentals positioned as if applying to notehead on bottom line
            // Accidentals are vertically centered on baseline
            yOffset = symbolSize / 2
        } else if isClef {
            // SMuFL: Clefs positioned with pitch reference on baseline
            // For visual centering, position the clef center at the point
            yOffset = symbolSize / 2
        } else {
            // For other symbols, center the entire glyph
            yOffset = symbolSize / 2
        }
        
        context.saveGState()
        context.translateBy(x: point.x - symbolSize/2, y: point.y - yOffset)
        
        // Fix the coordinate system for text rendering
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Set up the context for text rendering
        context.setAllowsFontSubpixelPositioning(true)
        context.setAllowsFontSubpixelQuantization(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setShouldSubpixelQuantizeFonts(true)
        
        // Create a Core Text line and draw it
        let line = CTLineCreateWithAttributedString(attributedString)
        context.textPosition = CGPoint.zero
        CTLineDraw(line, context)
        
        // Also try rendering a simple test character to verify font is working

        
        context.restoreGState()
    }
    
    /// Draw fallback symbol using simple line drawing
    private static func drawFallbackSymbol(_ symbol: String, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        context.setLineWidth(config.staffSize * 0.1)
        
        // Simple fallback drawing based on symbol type
        if symbol.contains("clef") {
            // Draw a simple clef symbol
            let size = config.staffSize * 2.0
            context.strokeEllipse(in: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        } else if symbol.contains("note") {
            // Draw a simple note head
            let size = config.staffSize * 0.8
            context.fillEllipse(in: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        } else {
            // Draw a simple cross for unknown symbols
            let size = config.staffSize * 1.0
            context.move(to: CGPoint(x: point.x - size/2, y: point.y - size/2))
            context.addLine(to: CGPoint(x: point.x + size/2, y: point.y + size/2))
            context.move(to: CGPoint(x: point.x - size/2, y: point.y + size/2))
            context.addLine(to: CGPoint(x: point.x + size/2, y: point.y - size/2))
            context.strokePath()
        }
        
        context.restoreGState()
    }
    
    /// Draw SMuFL clef
    static func drawSMuFLClef(_ clef: SalieriClef, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        let symbol: String
        switch clef.type {
        case .treble: symbol = "treble_clef"
        case .bass: symbol = "bass_clef"
        case .alto: symbol = "alto_clef"
        case .tenor: symbol = "tenor_clef"
        case .percussion: symbol = "percussion_clef"
        case .other(_): symbol = "treble_clef"
        }
        
        // Calculate staff line spacing for proper scaling
        let staffLineSpacing: CGFloat = config.staffSize * 1.0
        
        // SMuFL specification: clefs should be sized to fit the staff
        // Standard clef height is approximately 3 staff spaces
        let clefSize = staffLineSpacing * 3.0 // Clef height = 3 staff spaces
        
        // Adjust Y position to position the clef lower on the staff
        // Since the symbol is centered around the point, we need to move it down more
        let adjustedPoint = CGPoint(x: point.x, y: point.y + clefSize * 0.8)
        
        drawSMuFLSymbol(symbol, at: adjustedPoint, context: context, config: config, size: clefSize)
    }
    
    /// Draw SMuFL note
    static func drawSMuFLNote(_ note: SalieriNotehead, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        let symbol: String
        switch note.note.duration {
        case .whole: symbol = "whole_note"
        case .half: symbol = "half_note"
        case .quarter: symbol = "quarter_note"
        case .eighth: symbol = "eighth_note"
        case .sixteenth: symbol = "sixteenth_note"
        case .thirtySecond: symbol = "thirty_second_note"
        case .sixtyFourth: symbol = "sixty_fourth_note"
        case .dotted(_, _): symbol = "quarter_note" // Will add dot separately
        case .custom(_): symbol = "quarter_note"
        }
        
        // Calculate staff line spacing for proper scaling
        let staffLineSpacing: CGFloat = config.staffSize * 1.0
        
        // SMuFL specification: one staff space = 0.25 em
        // For proper sizing, we need to scale the glyph to match our staff line spacing
        // If staff line spacing = 0.25 em, then 1 em = 4 × staff line spacing
        let emSize = staffLineSpacing * 4.0 // 1 em = 4 staff spaces
        let noteSize = emSize // Size the entire glyph to 1 em (standard SMuFL sizing)
        
        drawSMuFLSymbol(symbol, at: point, context: context, config: config, size: noteSize)
        

        
        // Draw dots if needed
        if case let .dotted(_, dots) = note.note.duration {
            for i in 0..<dots {
                let dotOffset = CGFloat(i + 1) * staffLineSpacing * 0.8
                let dotPoint = CGPoint(x: point.x + dotOffset, y: point.y)
                let dotSize = staffLineSpacing * 0.4 // Dots should be about 40% of staff line spacing
                drawSMuFLSymbol("augmentation_dot", at: dotPoint, context: context, config: config, size: dotSize)
            }
        }
    }
    
    /// Draw SMuFL accidental
    static func drawSMuFLAccidental(_ accidental: SalieriAccidental, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        let symbol: String
        switch accidental {
        case .sharp: symbol = "sharp"
        case .flat: symbol = "flat"
        case .natural: symbol = "natural"
        case .doubleSharp: symbol = "double_sharp"
        case .doubleFlat: symbol = "double_flat"
        case .quarterSharp: symbol = "quarter_sharp"
        case .quarterFlat: symbol = "quarter_flat"
        case .threeQuarterSharp: symbol = "three_quarter_sharp"
        case .threeQuarterFlat: symbol = "three_quarter_flat"
        case .other(_): symbol = "sharp"
        }
        
        // Calculate staff line spacing for proper scaling
        let staffLineSpacing: CGFloat = config.staffSize * 1.0
        
        // SMuFL specification: accidentals should be sized relative to staff line spacing
        // Standard accidental height is approximately 2 staff spaces
        let accidentalSize = staffLineSpacing * 2.0 // Accidental height = 2 staff spaces
        
        drawSMuFLSymbol(symbol, at: point, context: context, config: config, size: accidentalSize)
    }
    

}


// MARK: - MIDI Parsing (Stub)

class SalieriMIDIParser {
    static func parseMIDIFile(at url: URL) -> MusicSequence? {
        // 1. Create a new MusicSequence
        var sequence: MusicSequence? = nil
        NewMusicSequence(&sequence)
        // 2. Load MIDI file into sequence
        if let seq = sequence {
            let status = MusicSequenceFileLoad(seq, url as CFURL, .midiType, MusicSequenceLoadFlags())
            if status == noErr {
                return seq
            }
        }
        return nil
    }
}
