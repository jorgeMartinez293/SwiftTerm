#if os(macOS)
import Foundation
import Testing

@testable import SwiftTerm

/// Rows that a program redraws in place must not keep the soft-wrap flag a resize
/// reflow gave them, or the next resize merges unrelated lines together.
final class WrapFlagTests {
    func makeTerminal(cols: Int) -> Terminal {
        let options = TerminalOptions(cols: cols, rows: 10, scrollback: 100)
        let h = HeadlessTerminal(queue: SwiftTermTests.queue, options: options) { _ in }
        return h.terminal!
    }

    func rows(_ t: Terminal) -> [String] {
        (0..<t.buffer.lines.count).map {
            t.buffer.translateBufferLineToString(lineIndex: $0, trimRight: true)
        }
    }

    let oldFrame = ["AAAAAAAAAAAAAAAAAAAAAAAAA", "BBBBBBBBBBBBBBBBBBBBBBBBB", "CCCCCCCCCCCCCCCCCCCCCCCCC"]
    let newFrame = ["aaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbb", "ccccccccccccccc"]

    /// Ink-style redraw: erase the previous frame line by line (EL 2 + cursor up),
    /// then write the new one.
    @Test func eraseLineRedrawIsNotMergedOnWiden() {
        let t = makeTerminal(cols: 30)
        t.feed(text: oldFrame.joined(separator: "\r\n"))
        t.resize(cols: 20, rows: 10)
        t.feed(text: "\u{1b}[2K\u{1b}[1A\u{1b}[2K\u{1b}[1A\u{1b}[2K\u{1b}[G")
        t.feed(text: newFrame.joined(separator: "\r\n"))
        t.resize(cols: 40, rows: 10)

        let r = rows(t)
        for line in newFrame {
            #expect(r.contains(line))
        }
    }

    /// Redraw by moving the cursor up and overwriting rows separated by line feeds,
    /// without erasing them first.
    @Test func lineFeedRedrawIsNotMergedOnWiden() {
        let t = makeTerminal(cols: 30)
        t.feed(text: oldFrame.joined(separator: "\r\n"))
        t.resize(cols: 20, rows: 10)
        // The old frame now spans 6 rows; go back to its second row and redraw.
        t.feed(text: "\u{1b}[4A\r")
        t.feed(text: newFrame.map { $0 + "\u{1b}[K" }.joined(separator: "\r\n"))
        t.resize(cols: 40, rows: 10)

        let r = rows(t)
        #expect(r.contains("bbbbbbbbbbbbbbb"))
        #expect(r.contains("ccccccccccccccc"))
    }

    /// Autowrap with history above the screen and the cursor off the bottom row (a TUI
    /// redrawing its frame) must flag the row the text wraps into, not the row at the
    /// same index counted from the top of the scrollback.
    @Test func autowrapWithScrollbackFlagsTheRightRow() {
        for ascii in [true, false] {
            let t = makeTerminal(cols: 10)
            t.feed(text: (0..<15).map { "line\($0)" }.joined(separator: "\r\n"))
            #expect(t.buffer.yBase > 0)

            // Back to the top of the screen and write text that autowraps once.
            t.feed(text: "\u{1b}[H")
            t.feed(text: ascii ? "0123456789abc" : "0123456789äbc")

            let top = t.buffer.yBase
            for row in 0..<t.buffer.lines.count {
                #expect(t.buffer.lines[row].isWrapped == (row == top + 1), "row \(row)")
            }
        }
    }

    /// Once the scrollback is full, scrolling recycles the oldest line as the new bottom
    /// row. It must come back as a plain new line, not keep the soft-wrap flag of the line
    /// it used to hold (which merged unrelated lines on the next resize).
    @Test func recycledLinesDoNotInheritWrapFlag() {
        let options = TerminalOptions(cols: 10, rows: 3, scrollback: 2)
        let h = HeadlessTerminal(queue: SwiftTermTests.queue, options: options) { _ in }
        let t = h.terminal!
        // Two autowrapped lines, so the oldest rows in the buffer carry the flag...
        t.feed(text: "0123456789abc\r\n0123456789def\r\n")
        // ...then enough short lines to recycle every row.
        t.feed(text: (1...12).map { "x\($0)" }.joined(separator: "\r\n"))
        #expect(t.buffer.lines.count == t.buffer.lines.maxLength)
        for row in 0..<t.buffer.lines.count {
            #expect(!t.buffer.lines[row].isWrapped, "row \(row)")
        }

        // An autowrap that recycles a line still flags it.
        t.feed(text: "\r\n0123456789ghi")
        let last = t.buffer.lines.count - 1
        #expect(t.buffer.lines[last].isWrapped)
        #expect(!t.buffer.lines[last - 1].isWrapped)

        // And the round trip keeps every line intact.
        t.resize(cols: 4, rows: 3)
        t.resize(cols: 10, rows: 3)
        let r = rows(t)
        #expect(r.contains("x12"))
        #expect(!r.contains { $0.hasPrefix("x") && $0.count > 3 })
    }

    /// Genuine autowrapped text still reflows back into one line.
    @Test func autowrappedTextStillJoinsOnWiden() {
        let t = makeTerminal(cols: 10)
        t.feed(text: "0123456789abcdefghij\r\nnext")
        t.resize(cols: 30, rows: 10)

        let r = rows(t)
        #expect(r.contains("0123456789abcdefghij"))
        #expect(r.contains("next"))
    }
}
#endif
