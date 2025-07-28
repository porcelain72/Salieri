# Contributing to Salieri

Thank you for your interest in contributing to Salieri! This document provides guidelines and information for contributors.

## Development Setup

### Prerequisites

- macOS 13.5+ or iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Git

### Getting Started

1. **Fork the repository**
   ```bash
   git clone https://github.com/yourusername/Salieri.git
   cd Salieri
   ```

2. **Open in Xcode**
   ```bash
   open Package.swift
   ```

3. **Run tests to ensure everything works**
   ```bash
   swift test
   ```

## Development Guidelines

### Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions focused and concise
- Use Swift's type system effectively

### Testing

- Write tests for all new functionality
- Ensure existing tests continue to pass
- Test on both macOS and iOS when applicable
- Include edge cases and error conditions

### Commit Messages

Use conventional commit format:
```
type(scope): description

[optional body]

[optional footer]
```

Examples:
- `feat(engraving): add slur support`
- `fix(parsing): resolve time signature meta event issue`
- `docs(readme): update installation instructions`

### Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write code following the style guidelines
   - Add tests for new functionality
   - Update documentation if needed

3. **Test your changes**
   ```bash
   swift test
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat(scope): description"
   ```

5. **Push and create a pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

## Areas for Contribution

### High Priority
- **Time Signature Parsing**: Fix the current -10855 error in meta event parsing
- **Advanced Beaming**: Implement more sophisticated beaming rules
- **Performance Optimization**: Improve rendering speed for large scores

### Medium Priority
- **Text Elements**: Add support for lyrics, dynamics, and articulations
- **Slurs and Ties**: Implement curved lines and tie notation
- **Custom Fonts**: Support for custom music fonts and glyphs

### Low Priority
- **Guitar Tablature**: Add tablature support
- **Advanced Layout**: More sophisticated page layout algorithms
- **Export Formats**: Support for other output formats (SVG, PNG)

## Architecture Overview

Salieri follows a modular architecture:

```
Sources/Salieri/
├── Salieri.swift          # Main API and public interfaces
├── Models/                # Internal music model types
├── Parsing/               # MIDI and MusicSequence parsing
├── Engraving/             # Layout and engraving engine
└── Rendering/             # PDF generation
```

### Key Components

1. **Input Layer**: Handles MusicSequence and MIDI file parsing
2. **Music Model**: Internal representation of musical data
3. **Engraving Engine**: Converts music data to visual layout
4. **PDF Renderer**: Generates final PDF output

## Testing Guidelines

### Running Tests
```bash
# Run all tests
swift test

# Run specific test
swift test --filter SalieriTests.testSingleNoteParsing

# Run with verbose output
swift test -v
```

### Writing Tests
- Test both success and failure cases
- Use descriptive test names
- Test edge cases and boundary conditions
- Mock external dependencies when appropriate

### Test Structure
```swift
func testFeatureName() {
    // Arrange - Set up test data
    let input = createTestInput()
    
    // Act - Execute the code being tested
    let result = functionUnderTest(input)
    
    // Assert - Verify the expected outcome
    XCTAssertEqual(result, expectedValue)
}
```

## Documentation

### Code Documentation
- Document all public APIs with Swift documentation comments
- Include usage examples in documentation
- Keep documentation up to date with code changes

### README Updates
- Update README.md when adding new features
- Include code examples for new functionality
- Update installation instructions if needed

## Release Process

### Versioning
Salieri follows [Semantic Versioning](https://semver.org/):
- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality in a backwards-compatible manner
- **PATCH**: Backwards-compatible bug fixes

### Release Checklist
- [ ] All tests pass
- [ ] Documentation is up to date
- [ ] Version number is updated
- [ ] CHANGELOG.md is updated
- [ ] Release notes are prepared

## Getting Help

- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and general discussion
- **Code Review**: All contributions require review before merging

## Code of Conduct

This project is committed to providing a welcoming and inclusive environment for all contributors. Please be respectful and constructive in all interactions.

## License

By contributing to Salieri, you agree that your contributions will be licensed under the MIT License. 