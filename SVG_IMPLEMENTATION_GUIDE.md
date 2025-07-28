# SVG Implementation Guide for Salieri

## Overview

Salieri now supports SVG-based rendering for musical notation symbols, providing authentic, professionally engraved appearance. This implementation uses SVG files from the [Wikimedia Commons SVG musical notation collection](https://commons.wikimedia.org/wiki/Category:SVG_musical_notation) and converts them to Core Graphics paths for PDF rendering.

## Architecture

### SVG Renderer Class

The `SalieriSVGRenderer` class handles all SVG-based rendering:

```swift
class SalieriSVGRenderer {
    private static let svgCache = NSCache<NSString, CGPath>()
    
    // Main rendering methods
    static func drawSVGClef(_ clef: SalieriClef, at point: CGPoint, context: CGContext, config: SalieriConfiguration)
    static func drawSVGNote(_ note: SalieriNotehead, at point: CGPoint, context: CGContext, config: SalieriConfiguration)
    static func drawSVGRest(_ rest: SalieriRest, at point: CGPoint, context: CGContext, config: SalieriConfiguration)
    static func drawSVGAccidental(_ accidental: SalieriAccidental, at point: CGPoint, context: CGContext, config: SalieriConfiguration)
}
```

### Key Features

1. **SVG Path Parsing**: Converts SVG path data to Core Graphics paths
2. **Caching**: SVG paths are cached for performance
3. **Fallback System**: Falls back to line-drawn symbols if SVG files are missing
4. **Multi-Format Support**: Handles paths, circles, lines, and ellipses
5. **Scaling**: Automatically scales SVG content to match staff size

## SVG File Structure

### Directory Layout
```
Sources/Salieri/Resources/
├── treble_clef.svg      # Professional treble clef
├── bass_clef.svg        # Professional bass clef
├── alto_clef.svg        # Professional alto clef
├── tenor_clef.svg       # Professional tenor clef
├── quarter_note.svg     # Quarter note with stem
├── half_note.svg        # Half note (open notehead)
├── whole_note.svg       # Whole note (open notehead)
├── eighth_note.svg      # Eighth note with flag
├── sixteenth_note.svg   # Sixteenth note with flags
├── sharp.svg            # Sharp accidental
├── flat.svg             # Flat accidental
├── natural.svg          # Natural accidental
└── ...                  # Additional notation symbols
```

### SVG File Format

SVG files should be simple and optimized for path extraction:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <!-- Use simple shapes for best compatibility -->
  <path d="M 50 10 L 50 90..." stroke="black" stroke-width="3" fill="none"/>
  <circle cx="35" cy="35" r="8" fill="black"/>
  <line x1="10" y1="5" x2="10" y2="25" stroke="black" stroke-width="2"/>
  <ellipse cx="25" cy="15" rx="8" ry="6" fill="black"/>
</svg>
```

## Implementation Details

### SVG Path Parser

The parser extracts multiple SVG element types:

```swift
private static func parseSVGPath(_ svgContent: String) -> CGPath? {
    let path = CGMutablePath()
    
    // Extract path data
    let pathPattern = #"<path[^>]*d="([^"]*)"[^>]*>"#
    
    // Extract circle data
    let circlePattern = #"<circle[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*r="([^"]*)"[^>]*>"#
    
    // Extract line data
    let linePattern = #"<line[^>]*x1="([^"]*)"[^>]*y1="([^"]*)"[^>]*x2="([^"]*)"[^>]*y2="([^"]*)"[^>]*>"#
    
    // Extract ellipse data
    let ellipsePattern = #"<ellipse[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*rx="([^"]*)"[^>]*ry="([^"]*)"[^>]*>"#
    
    return path
}
```

### Path Data Parser

Converts SVG path commands to Core Graphics operations:

```swift
private static func parseSVGPathData(_ pathData: String) -> CGPath? {
    let path = CGMutablePath()
    let commands = pathData.components(separatedBy: .whitespacesAndNewlines)
    
    // Handle SVG path commands:
    // M = Move to (absolute)
    // L = Line to (absolute)
    // C = Cubic curve (absolute)
    // Q = Quadratic curve (absolute)
    // Z = Close path
    
    return path
}
```

### Caching System

SVG paths are cached for performance:

```swift
private static let svgCache = NSCache<NSString, CGPath>()

private static func loadSVGPath(_ name: String) -> CGPath? {
    let cacheKey = NSString(string: name)
    
    // Check cache first
    if let cachedPath = svgCache.object(forKey: cacheKey) {
        return cachedPath
    }
    
    // Load and parse SVG
    guard let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
          let svgData = try? Data(contentsOf: svgURL),
          let svgString = String(data: svgData, encoding: .utf8),
          let path = parseSVGPath(svgString) else {
        return nil
    }
    
    // Cache the path
    svgCache.setObject(path, forKey: cacheKey)
    return path
}
```

## Integration with PDF Renderer

The SVG renderer is integrated into the existing PDF rendering pipeline:

```swift
// In SalieriPDFRenderer
private static func drawClef(_ clef: SalieriClef, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
    // Use SVG renderer with fallback to line-drawn clefs
    SalieriSVGRenderer.drawSVGClef(clef, at: point, context: context, config: config)
}

private static func drawNotehead(_ notehead: SalieriNotehead, xBase: CGFloat, yBase: CGFloat, context: CGContext, config: SalieriConfiguration) {
    // Draw SVG note
    SalieriSVGRenderer.drawSVGNote(notehead, at: CGPoint(x: xBase, y: yBase + notehead.y), context: context, config: config)
    
    // Draw SVG accidental
    if let accidental = notehead.accidental {
        SalieriSVGRenderer.drawSVGAccidental(accidental, at: accidentalPoint, context: context, config: config)
    }
}
```

## Fallback System

If SVG files are missing or fail to load, the system falls back to simple line-drawn symbols:

```swift
guard let path = loadSVGPath(svgName) else {
    // Fallback to simple drawing
    drawSimpleNote(note, at: point, context: context, config: config)
    return
}
```

## Adding New SVG Files

### Step 1: Create SVG File

1. Find a suitable SVG from [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:SVG_musical_notation)
2. Optimize the SVG for path extraction (remove unnecessary attributes)
3. Save with appropriate filename (e.g., `whole_note.svg`)

### Step 2: Add to Resources

Place the SVG file in `Sources/Salieri/Resources/`

### Step 3: Update Renderer

Add the new symbol to the appropriate rendering method:

```swift
static func drawSVGNote(_ note: SalieriNotehead, at point: CGPoint, context: CGContext, config: SalieriConfiguration) {
    let svgName: String
    
    switch note.duration {
    case .whole: svgName = "whole_note"
    case .half: svgName = "half_note"
    case .quarter: svgName = "quarter_note"
    // Add new cases here
    }
    
    // ... rest of implementation
}
```

## Testing SVG Rendering

### Visual Tests

Run the SVG-specific tests to verify rendering:

```bash
swift test --filter testSVGRendering
swift test --filter testSVGClefRendering
```

### Generated Test PDFs

The tests generate PDFs for manual inspection:

- `svg_rendering_test.pdf`: Tests SVG note and clef rendering
- `svg_clef_test.pdf`: Tests SVG clef rendering specifically

### Verification Checklist

When inspecting the generated PDFs:

- [ ] Clefs appear more detailed than simple lines
- [ ] Notes have proper notehead shapes
- [ ] Accidentals are clearly visible
- [ ] Symbols scale properly with staff size
- [ ] Fallback symbols appear if SVG files are missing

## Performance Considerations

### Caching Benefits

- SVG paths are parsed once and cached
- Subsequent renders use cached paths
- Memory usage is controlled by NSCache

### File Size Optimization

- Keep SVG files small and simple
- Use basic shapes (path, circle, line, ellipse)
- Remove unnecessary SVG attributes
- Optimize path data for parsing

### Rendering Performance

- SVG parsing happens at load time, not render time
- Core Graphics paths are efficient for PDF rendering
- Fallback system ensures rendering always works

## Future Enhancements

### Planned Improvements

1. **More SVG Symbols**: Add support for all musical notation symbols
2. **Advanced Path Parsing**: Support more SVG path commands
3. **Dynamic Scaling**: Better scaling algorithms for different staff sizes
4. **Custom SVG Support**: Allow users to provide custom SVG files
5. **Vector Fonts**: Integrate with music fonts for text elements

### Potential Optimizations

1. **Pre-compiled Paths**: Compile SVG paths at build time
2. **Lazy Loading**: Load SVG files only when needed
3. **Path Simplification**: Simplify complex paths for better performance
4. **Batch Rendering**: Optimize for rendering multiple symbols

## Troubleshooting

### Common Issues

1. **SVG Not Rendering**: Check that SVG file exists in Resources directory
2. **Wrong Scaling**: Verify SVG viewBox matches expected dimensions
3. **Missing Symbols**: Ensure fallback system is working
4. **Performance Issues**: Check SVG file complexity and caching

### Debug Information

Enable debug output to see SVG loading status:

```swift
#if DEBUG
print("Loading SVG: \(svgName)")
if let path = loadSVGPath(svgName) {
    print("SVG loaded successfully")
} else {
    print("SVG failed to load, using fallback")
}
#endif
```

## Conclusion

The SVG implementation provides Salieri with authentic, professionally engraved musical notation while maintaining the reliability of the existing line-drawn system. The modular design allows for easy expansion and the fallback system ensures the package remains robust even when SVG files are missing.

This implementation leverages the rich collection of SVG musical notation available from Wikimedia Commons, making it easy to add new symbols and maintain professional quality across all rendered scores. 