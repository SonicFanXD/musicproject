import XCTest
@testable import AuroraPlayer

final class LyricsEngineTests: XCTestCase {

    private func makeTokens() -> [LyricsToken] {
        [
            LyricsToken(id: "w0", text: "Hola", startMs: 0, endMs: 400, lineIndex: 0, wordIndex: 0, lane: 0),
            LyricsToken(id: "w1", text: "mundo", startMs: 400, endMs: 900, lineIndex: 0, wordIndex: 1, lane: 0),
            LyricsToken(id: "w2", text: "otra", startMs: 2000, endMs: 2300, lineIndex: 1, wordIndex: 0, lane: 0),
            LyricsToken(id: "w3", text: "línea", startMs: 2300, endMs: 2800, lineIndex: 1, wordIndex: 1, lane: 0)
        ]
    }

    private func makeLines() -> [LyricsLine] {
        [
            LyricsLine(id: "l0", lineIndex: 0, startMs: 0, endMs: 900, tokenIDs: ["w0", "w1"]),
            LyricsLine(id: "l1", lineIndex: 1, startMs: 2000, endMs: 2800, tokenIDs: ["w2", "w3"])
        ]
    }

    func testAntesDelPrimerToken_sinTokenActivo() {
        let engine = LyricsEngine(tokens: makeTokens(), lines: makeLines())
        let state = engine.state(at: -50)
        XCTAssertNil(state.activeTokenID)
        XCTAssertNil(state.activeLineIndex)
        XCTAssertEqual(state.nextTokenID, "w0")
    }

    func testMitadDeToken_progresoInterpoladoCorrectamente() {
        let engine = LyricsEngine(tokens: makeTokens(), lines: makeLines())
        // w0: 0-400ms; en 200ms debe estar a la mitad.
        let state = engine.state(at: 200)
        XCTAssertEqual(state.activeTokenID, "w0")
        XCTAssertEqual(state.activeLineIndex, 0)
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.001)
    }

    func testLimiteExactoDeToken_cambiaAlSiguiente() {
        let engine = LyricsEngine(tokens: makeTokens(), lines: makeLines())
        let state = engine.state(at: 400)
        XCTAssertEqual(state.activeTokenID, "w1")
        XCTAssertEqual(state.previousTokenID, "w0")
        XCTAssertEqual(state.progress, 0, accuracy: 0.001)
    }

    func testHuecoEntreLineas_seMantieneStickyEnUltimoToken() {
        // Verifica el diseño "sticky" elegido: en el silencio entre la
        // línea 0 (termina 900ms) y la línea 1 (empieza 2000ms), el token
        // activo se mantiene en w1 con progress saturado a 1.0.
        let engine = LyricsEngine(tokens: makeTokens(), lines: makeLines())
        let state = engine.state(at: 1500)
        XCTAssertEqual(state.activeTokenID, "w1")
        XCTAssertEqual(state.activeLineIndex, 0)
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.001)
    }

    func testDespuesDelUltimoToken_progresoSaturaEnUno() {
        let engine = LyricsEngine(tokens: makeTokens(), lines: makeLines())
        let state = engine.state(at: 5000)
        XCTAssertEqual(state.activeTokenID, "w3")
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.001)
        XCTAssertNil(state.nextTokenID)
    }

    func testSinTokens_devuelveEstadoVacio() {
        let engine = LyricsEngine(tokens: [], lines: [])
        let state = engine.state(at: 0)
        XCTAssertNil(state.activeTokenID)
        XCTAssertNil(state.activeLineIndex)
    }

    func testTokenBuilder_asignaLineIndexYWordIndexCorrectamente() {
        let lyrics = SynchronizedLyrics(
            lines: [LyricLine(time: 0, text: "Hola mundo"), LyricLine(time: 2, text: "otra línea")],
            words: [
                LyricWord(time: 0, text: "Hola", duration: 0.4),
                LyricWord(time: 0.4, text: "mundo", duration: 0.5),
                LyricWord(time: 2.0, text: "otra", duration: 0.3),
                LyricWord(time: 2.3, text: "línea", duration: nil)
            ],
            isWordByWord: true
        )
        let (tokens, lines) = LyricsTokenBuilder.makeTokens(from: lyrics)

        XCTAssertEqual(tokens.map(\.lineIndex), [0, 0, 1, 1])
        XCTAssertEqual(tokens.map(\.wordIndex), [0, 1, 0, 1])
        XCTAssertEqual(lines.count, 2)
        // Última palabra sin duration → usa el default (400ms).
        XCTAssertEqual(tokens.last?.endMs, 2300 + 400)
    }
}