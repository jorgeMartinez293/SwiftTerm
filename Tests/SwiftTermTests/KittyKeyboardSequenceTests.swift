#if os(macOS)
import Foundation
import Testing
@testable import SwiftTerm

/// The kitty keyboard protocol shares the `u` final byte with SCORC (restore cursor);
/// programs such as pi and Claude Code send these on startup and exit.
final class KittyKeyboardSequenceTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    @Test func testKittyKeyboardSequencesDoNotMoveCursor () {
        let t = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 24))
        t.feed (text: "\u{1b}[20;11H")
        for sequence in ["\u{1b}[>7u", "\u{1b}[?u", "\u{1b}[<u", "\u{1b}[<1u", "\u{1b}[=1;1u"] {
            t.feed (text: sequence)
            #expect (t.buffer.x == 10, "\(sequence.debugDescription) moved the cursor")
            #expect (t.buffer.y == 19, "\(sequence.debugDescription) moved the cursor")
        }
    }

    @Test func testBareCsiURestoresCursor () {
        let t = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 24))
        t.feed (text: "\u{1b}[5;7H\u{1b}[s\u{1b}[20;1H\u{1b}[u")
        #expect (t.buffer.x == 6)
        #expect (t.buffer.y == 4)
    }
}
#endif
