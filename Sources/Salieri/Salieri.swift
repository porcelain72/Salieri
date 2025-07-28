import Foundation
import CoreGraphics
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
                }
            }
            
            // Map event to SalieriEvent
            if let event = mapEvent(eventType: eventType, eventData: eventData, timeStamp: timeStamp) {
                // Check if event crosses measure boundary
                let beatInMeasure = timeStamp - currentMeasureStartBeat
                if beatInMeasure >= beatsPerMeasure(currentTimeSignature) {
                    measures.append(SalieriMeasure(number: currentMeasureNumber, events: currentEvents))
                    currentMeasureNumber += 1
                    currentEvents = []
                    currentMeasureStartBeat += beatsPerMeasure(currentTimeSignature)
                }
                currentEvents.append(event)
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
            print("[DEBUG] metaEventType: \(meta.metaEventType), dataLength: \(meta.dataLength), metaData[0..4]:", metaData[0], metaData[1], metaData[2], metaData[3])
            if meta.metaEventType == 0x58, meta.dataLength >= 4 {
                let num = Int(metaData[0])
                let denom = Int(pow(2.0, Double(metaData[1])))
                print("[DEBUG] Parsed time signature: num=\(num), denom=\(denom)")
                let ts = SalieriTimeSignature(numerator: num, denominator: denom)
                return .timeSignature(ts)
            }
            if meta.metaEventType == 0x59, meta.dataLength >= 2 {
                let fifths = Int(Int8(bitPattern: metaData[0]))
                let mode = metaData[1] == 0 ? SalieriKeySignature.KeyMode.major : .minor
                print("[DEBUG] Parsed key signature: fifths=\(fifths), mode=\(mode)")
                let ks = SalieriKeySignature(fifths: fifths, mode: mode)
                return .keySignature(ks)
            }
            print("[DEBUG] Meta event not parsed: type=\(meta.metaEventType), length=\(meta.dataLength)")
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
        //
        // For now, implement basic logic for each advanced feature
        var pages: [SalieriPage] = []
        let systemSpacing: CGFloat = 120.0
        let staffSpacing: CGFloat = 80.0
        let measureWidth: CGFloat = 200.0 // Increased for better spacing
        let notesPerBeamGroup = 2 // Simple beaming: group every 2 eighth notes
        let staffLineSpacing: CGFloat = config.staffSize * 1.5 // Reduced spacing
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        var systemNumber = 1
        var pageNumber = 1
        var yOffset: CGFloat = config.margins.top
        var systems: [SalieriSystem] = []
        // For each part, create a staff
        let staves: [SalieriStaff] = score.parts.enumerated().map { (partIdx, part) in
            // Assume treble clef for now
            let clef = SalieriClef(type: .treble, line: 2)
            let measures: [SalieriMeasureLayout] = part.measures.enumerated().map { (mIdx, measure) in
                // Beaming: group notes for beaming
                var beamGroup = 0
                var beamCount = 0
                // Calculate proper note spacing based on duration
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
                        // Calculate horizontal position with proper spacing
                        let xSpacing = calculateNoteSpacing(for: note, measureWidth: measureWidth, totalNotes: measure.events.count)
                        return SalieriNotehead(note: note, x: xSpacing, y: y, accidental: accidental, ledgerLines: ledgerLines, stemDirection: stemDirection, beamGroup: group)
                    }
                    return nil
                }
                return SalieriMeasureLayout(events: events, xPosition: CGFloat(mIdx) * measureWidth, width: measureWidth, measureNumber: measure.number)
            }
            return SalieriStaff(measures: measures, partName: part.name, yPosition: yOffset + CGFloat(partIdx) * staffSpacing, staffNumber: partIdx + 1, clef: clef)
        }
        // Pagination: one system per page for now, but split if too many staves
        let system = SalieriSystem(staves: staves, yPosition: yOffset, systemNumber: systemNumber)
        systems.append(system)
        let page = SalieriPage(systems: systems, pageNumber: pageNumber)
        pages.append(page)
        return SalieriLayout(pages: pages)
    }
    
    // Helper: Calculate proper note spacing to prevent overprinting
    private static func calculateNoteSpacing(for note: SalieriNote, measureWidth: CGFloat, totalNotes: Int) -> CGFloat {
        // Use duration to determine spacing
        let baseSpacing = measureWidth / CGFloat(max(totalNotes, 1))
        let durationMultiplier: CGFloat
        switch note.duration {
        case .whole: durationMultiplier = 4.0
        case .half: durationMultiplier = 2.0
        case .quarter: durationMultiplier = 1.0
        case .eighth: durationMultiplier = 0.5
        case .sixteenth: durationMultiplier = 0.25
        case .thirtySecond: durationMultiplier = 0.125
        case .sixtyFourth: durationMultiplier = 0.0625
        case .dotted(_, _): durationMultiplier = 1.5 // Approximate
        case .custom(let v): durationMultiplier = CGFloat(v)
        }
        return baseSpacing * durationMultiplier
    }
    
    // Helper: Calculate vertical position for a pitch on the staff
    private static func yForPitch(_ pitch: SalieriPitch, clef: SalieriClef, staffLineSpacing: CGFloat, staffHeight: CGFloat) -> CGFloat {
        // For treble clef, C4 is one ledger line below staff
        // Staff lines: 0 (bottom) to 4 (top)
        // Middle C (C4) is y = staffHeight + staffLineSpacing
        let midiNumber = midiNumberForPitch(pitch)
        let c4 = 60
        let offset = midiNumber - c4
        // Each step is a line or space (up = negative y)
        let y = staffHeight + staffLineSpacing - CGFloat(offset) * (staffLineSpacing / 2)
        return y
    }
    // Helper: Calculate ledger lines for a pitch
    private static func ledgerLinesForPitch(_ pitch: SalieriPitch, clef: SalieriClef, staffLineSpacing: CGFloat, staffHeight: CGFloat) -> [LedgerLine] {
        // For now, add a ledger line for every note outside the 5 staff lines
        let y = yForPitch(pitch, clef: clef, staffLineSpacing: staffLineSpacing, staffHeight: staffHeight)
        var lines: [LedgerLine] = []
        if y < 0 { // Above staff
            let count = Int(abs(y) / (staffLineSpacing / 2) / 2)
            for i in 0..<count { lines.append(LedgerLine(y: -CGFloat(i+1) * staffLineSpacing, length: staffLineSpacing * 1.5)) }
        } else if y > staffHeight { // Below staff
            let count = Int((y - staffHeight) / (staffLineSpacing / 2) / 2)
            for i in 0..<count { lines.append(LedgerLine(y: staffHeight + CGFloat(i+1) * staffLineSpacing, length: staffLineSpacing * 1.5)) }
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
            drawStaff(staff, context: context, config: config)
        }
    }
    
    private static func drawStaff(_ staff: SalieriStaff, context: CGContext, config: SalieriConfiguration) {
        let staffLineSpacing: CGFloat = config.staffSize * 1.5 // Match engraving spacing
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        let yBase = staff.yPosition
        
        // Draw clef at the beginning of the staff
        drawClef(staff.clef, at: CGPoint(x: config.margins.left + 20, y: yBase), context: context, config: config)
        
        // Draw staff lines
        context.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
        context.setLineWidth(1.0)
        for i in 0..<staffLines {
            let y = yBase + CGFloat(i) * staffLineSpacing
            context.move(to: CGPoint(x: config.margins.left + 60, y: y)) // Start after clef
            context.addLine(to: CGPoint(x: config.pageSize.width - config.margins.right, y: y))
        }
        context.strokePath()
        
        // Draw measures
        for measure in staff.measures {
            drawMeasure(measure, yBase: yBase, context: context, config: config)
        }
    }
    
    private static func drawClef(_ clef: SalieriClef, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
        let fontSize = config.staffSize * 3.0
        let clefSymbol: String
        
        switch clef.type {
        case .treble: clefSymbol = "𝄞"
        case .bass: clefSymbol = "𝄢"
        case .alto: clefSymbol = "𝄡"
        case .tenor: clefSymbol = "𝄡"
        case .percussion: clefSymbol = "𝄤"
        case .other(_): clefSymbol = "𝄞" // Default to treble
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let attrStr = NSAttributedString(string: clefSymbol, attributes: attributes)
        attrStr.draw(at: point)
    }
    
    private static func drawMeasure(_ measure: SalieriMeasureLayout, yBase: CGFloat, context: CGContext, config: SalieriConfiguration) {
        // Draw measure line at start
        let xStart = config.margins.left + 60 + measure.xPosition // Account for clef space
        let xEnd = xStart + measure.width
        let staffLineSpacing: CGFloat = config.staffSize * 1.5
        let staffLines = 5
        let staffHeight = CGFloat(staffLines - 1) * staffLineSpacing
        
        context.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: xStart, y: yBase))
        context.addLine(to: CGPoint(x: xStart, y: yBase + staffHeight))
        context.strokePath()
        
        // Draw notes with proper spacing
        for (index, notehead) in measure.events.enumerated() {
            let xOffset = CGFloat(index) * 40.0 // Fixed spacing between notes
            drawNotehead(notehead, xBase: xStart + xOffset, yBase: yBase, context: context, config: config)
        }
        
        // Draw measure line at end
        context.move(to: CGPoint(x: xEnd, y: yBase))
        context.addLine(to: CGPoint(x: xEnd, y: yBase + staffHeight))
        context.strokePath()
    }
    
    private static func drawNotehead(_ notehead: SalieriNotehead, xBase: CGFloat, yBase: CGFloat, context: CGContext, config: SalieriConfiguration) {
        // Draw notehead as ellipse with proper scaling
        let noteRadius = config.staffSize * 0.8 // Smaller noteheads
        let x = xBase
        let y = yBase + notehead.y
        let noteRect = CGRect(x: x - noteRadius, y: y - noteRadius, width: noteRadius * 2, height: noteRadius * 1.5)
        
        context.setFillColor(CGColor(gray: 0, alpha: 1.0))
        context.fillEllipse(in: noteRect)
        
        // Draw stem with proper length
        let stemLength = config.staffSize * 3.5
        context.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
        context.setLineWidth(1.0)
        
        if notehead.stemDirection == .up {
            context.move(to: CGPoint(x: x + noteRadius, y: y))
            context.addLine(to: CGPoint(x: x + noteRadius, y: y - stemLength))
        } else {
            context.move(to: CGPoint(x: x - noteRadius, y: y))
            context.addLine(to: CGPoint(x: x - noteRadius, y: y + stemLength))
        }
        context.strokePath()
        
        // Draw accidentals with proper positioning
        if let accidental = notehead.accidental {
            let accidentalString = accidentalSymbol(accidental)
            let fontSize = config.staffSize * 1.2
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black
            ]
            let attrStr = NSAttributedString(string: accidentalString, attributes: attributes)
            let textPoint = CGPoint(x: x - noteRadius * 2.0, y: y - noteRadius * 0.5)
            attrStr.draw(at: textPoint)
        }
        
        // Draw ledger lines with proper positioning
        context.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
        context.setLineWidth(1.0)
        for ledger in notehead.ledgerLines {
            context.move(to: CGPoint(x: x - noteRadius * 1.2, y: yBase + ledger.y))
            context.addLine(to: CGPoint(x: x + noteRadius * 1.2, y: yBase + ledger.y))
        }
        context.strokePath()
    }
    
    private static func accidentalSymbol(_ accidental: SalieriAccidental) -> String {
        switch accidental {
        case .sharp: return "♯"
        case .flat: return "♭"
        case .natural: return "♮"
        case .doubleSharp: return "𝄪"
        case .doubleFlat: return "𝄫"
        case .quarterSharp: return "𝄲" // Placeholder
        case .quarterFlat: return "𝄳" // Placeholder
        case .threeQuarterSharp: return "𝄴" // Placeholder
        case .threeQuarterFlat: return "𝄵" // Placeholder
        case .other(let s): return s
        }
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
