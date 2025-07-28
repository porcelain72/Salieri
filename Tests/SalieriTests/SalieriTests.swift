import XCTest
import AudioToolbox
@testable import Salieri

final class SalieriTests: XCTestCase {
    func testSingleNoteParsing() {
        var sequence: MusicSequence? = nil
        NewMusicSequence(&sequence)
        guard let seq = sequence else { XCTFail("Failed to create sequence"); return }
        var track: MusicTrack? = nil
        MusicSequenceNewTrack(seq, &track)
        guard let trk = track else { XCTFail("Failed to create track"); return }
        var note = MIDINoteMessage(channel: 0, note: 60, velocity: 64, releaseVelocity: 0, duration: 1.0)
        MusicTrackNewMIDINoteEvent(trk, 0.0, &note)
        let score = SalieriScore.from(sequence: seq)
        XCTAssertEqual(score.parts.count, 1)
        let part = score.parts[0]
        XCTAssertEqual(part.measures.count, 1)
        let events = part.measures[0].events
        guard case let .note(parsedNote) = events.first else { XCTFail("First event is not a note"); return }
        XCTAssertEqual(parsedNote.pitch.step, .C)
        XCTAssertEqual(parsedNote.pitch.octave, 4)
    }
    
    func testTimeAndKeySignatureParsing() {
        var sequence: MusicSequence? = nil
        NewMusicSequence(&sequence)
        guard let seq = sequence else { XCTFail("Failed to create sequence"); return }
        var track: MusicTrack? = nil
        MusicSequenceNewTrack(seq, &track)
        guard let trk = track else { XCTFail("Failed to create track"); return }
        // Add time signature meta event (3/4)
        var timeSigBytes: [UInt8] = [3, 2, 24, 8] + Array(repeating: 0, count: 28)
        var meta = MIDIMetaEvent()
        meta.metaEventType = 0x58
        meta.dataLength = 4
        withUnsafeBytes(of: &timeSigBytes) { rawBuf in
            withUnsafeMutablePointer(to: &meta.data) { tuplePtr in
                UnsafeMutableRawPointer(tuplePtr).copyMemory(from: rawBuf.baseAddress!, byteCount: 32)
            }
        }
        MusicTrackNewMetaEvent(trk, 0.0, &meta)
        // Add key signature meta event (2 sharps, major)
        var keySigBytes: [UInt8] = [2, 0] + Array(repeating: 0, count: 30)
        var meta2 = MIDIMetaEvent()
        meta2.metaEventType = 0x59
        meta2.dataLength = 2
        withUnsafeBytes(of: &keySigBytes) { rawBuf in
            withUnsafeMutablePointer(to: &meta2.data) { tuplePtr in
                UnsafeMutableRawPointer(tuplePtr).copyMemory(from: rawBuf.baseAddress!, byteCount: 32)
            }
        }
        MusicTrackNewMetaEvent(trk, 0.0, &meta2)
        let score = SalieriScore.from(sequence: seq)
        // Print all events for debugging
        for (idx, measure) in score.parts[0].measures.enumerated() {
            print("Measure \(idx+1):", measure.events)
        }
        // Check all measures for time/key signature events
        let allEvents = score.parts[0].measures.flatMap { $0.events }
        XCTAssert(allEvents.contains { if case .timeSignature(_) = $0 { return true } else { return false } })
        XCTAssert(allEvents.contains { if case .keySignature(_) = $0 { return true } else { return false } })
    }
    
    func testRestDetection() {
        var sequence: MusicSequence? = nil
        NewMusicSequence(&sequence)
        guard let seq = sequence else { XCTFail("Failed to create sequence"); return }
        var track: MusicTrack? = nil
        MusicSequenceNewTrack(seq, &track)
        guard let trk = track else { XCTFail("Failed to create track"); return }
        var note1 = MIDINoteMessage(channel: 0, note: 60, velocity: 64, releaseVelocity: 0, duration: 0.5)
        var note2 = MIDINoteMessage(channel: 0, note: 62, velocity: 64, releaseVelocity: 0, duration: 0.5)
        MusicTrackNewMIDINoteEvent(trk, 0.0, &note1)
        MusicTrackNewMIDINoteEvent(trk, 1.0, &note2) // 0.5 beat rest between notes
        let score = SalieriScore.from(sequence: seq)
        let events = score.parts[0].measures[0].events
        XCTAssert(events.contains { if case .rest(_) = $0 { return true } else { return false } })
    }
    
    func testMeasureGrouping() {
        var sequence: MusicSequence? = nil
        NewMusicSequence(&sequence)
        guard let seq = sequence else { XCTFail("Failed to create sequence"); return }
        var track: MusicTrack? = nil
        MusicSequenceNewTrack(seq, &track)
        guard let trk = track else { XCTFail("Failed to create track"); return }
        // Add 5 quarter notes (should span 2 measures in 4/4)
        for i in 0..<5 {
            var note = MIDINoteMessage(channel: 0, note: 60, velocity: 64, releaseVelocity: 0, duration: 1.0)
            MusicTrackNewMIDINoteEvent(trk, Float64(i), &note)
        }
        let score = SalieriScore.from(sequence: seq)
        XCTAssertEqual(score.parts[0].measures.count, 2)
    }
    
    func testPDFRendering() {
        // Create a simple score with one part, one measure, one note
        let note = SalieriNote(
            pitch: SalieriPitch(step: .C, octave: 4, alter: nil),
            duration: .quarter,
            accidental: nil,
            stemDirection: nil,
            beamType: nil,
            isChord: false
        )
        let measure = SalieriMeasure(number: 1, events: [.note(note)])
        let part = SalieriPart(name: "Test Part", measures: [measure])
        let score = SalieriScore(title: "Test Score", parts: [part], isFullScore: true)
        let config = SalieriConfiguration()
        let layout = SalieriEngraver.engrain(score: score, config: config)
        let pdf = SalieriPDFRenderer.render(layout: layout, config: config)
        XCTAssertNotNil(pdf)
        XCTAssertGreaterThan(pdf?.pageCount ?? 0, 0)
        // Optionally, write to temp file for manual inspection
        if let pdf = pdf, let data = pdf.dataRepresentation() {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SalieriTestOutput.pdf")
            try? data.write(to: tempURL)
            print("PDF written to \(tempURL.path)")
        }
    }
}
