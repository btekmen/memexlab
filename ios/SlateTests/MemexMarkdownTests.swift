import XCTest
@testable import Slate

/// Pins the on-disk contract to what notes/notes.js and notes/bridge.py produce.
final class MemexMarkdownTests: XCTestCase {
    let when = Date(timeIntervalSince1970: 1_774_000_020) // 2026-03-20T10:27:00Z

    func testSlugifyMatchesMcp() {
        XCTAssertEqual(MemexMarkdown.slugify("Köprü testi: ilk not"), "k-pr-testi-ilk-not")
        XCTAssertEqual(MemexMarkdown.slugify("  --Hello, World!--  "), "hello-world")
        XCTAssertEqual(MemexMarkdown.slugify("???"), "note")
        XCTAssertEqual(MemexMarkdown.slugify(String(repeating: "a", count: 100)).count, 80)
    }

    func testYamlQuoting() {
        XCTAssertEqual(MemexMarkdown.yq(#"a "b" \ c"#), #""a \"b\" \\ c""#)
        XCTAssertEqual(MemexMarkdown.yq("x\ny"), #""x\ny""#)
        XCTAssertEqual(MemexMarkdown.yq("İkinci"), "\"İkinci\"")
    }

    func testInboxRenderFollowsCaptureAnywhereContract() {
        let c = Capture(title: "Bloomberg: rails", body: "> quote\n\nhttps://x.y/z\n\n", tags: ["topic/a", "reaction/b"],
                        sources: ["[[memexlab]]", "https://x.y/z"], capturedVia: "slate-ios", capturedAt: when)
        let md = MemexMarkdown.render(c, writeDir: "inbox")
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines[0], "---")
        XCTAssertEqual(lines[1], "title: \"Bloomberg: rails\"")
        XCTAssertEqual(lines[2], "status: \"inbox\"")
        XCTAssertEqual(lines[3], "captured_via: \"slate-ios\"")
        XCTAssertTrue(lines[4].hasPrefix("captured_at: \"2026-03-20T"))
        XCTAssertEqual(lines[5], "source_url: \"https://x.y/z\"")
        XCTAssertEqual(lines[6], "sources:")
        XCTAssertEqual(lines[7], "- \"[[memexlab]]\"")
        XCTAssertEqual(lines[8], "- \"https://x.y/z\"")
        XCTAssertEqual(lines[9], "tags: [\"topic/a\", \"reaction/b\"]")
        XCTAssertEqual(lines[10], "---")
        XCTAssertEqual(lines[11], "")
        XCTAssertTrue(md.hasSuffix("https://x.y/z\n"), "body is trimmed and ends with one newline")
    }

    func testEmptySourcesRenderAsEmptyList() {
        let md = MemexMarkdown.render(Capture(title: "t", body: "b", capturedAt: when), writeDir: "inbox")
        XCTAssertTrue(md.contains("\nsources: []\n"))
        XCTAssertFalse(md.contains("tags:"))
    }

    func testDailyRender() {
        let md = MemexMarkdown.render(Capture(title: "2026-03-20", body: MemexMarkdown.dailySkeleton("2026-03-20"), capturedAt: when, day: "2026-03-20"), writeDir: "daily")
        XCTAssertTrue(md.hasPrefix("---\ndate: 2026-03-20\ntype: daily\ncaptured_via: \"slate-ios\"\nupdated: \""))
        XCTAssertTrue(md.contains("\n---\n\n# 2026-03-20\n## What I did\n"))
    }

    func testFilenames() {
        let c = Capture(title: "Köprü testi: ilk not", body: "", capturedAt: when)
        XCTAssertEqual(MemexMarkdown.filename(c, style: .slug), "k-pr-testi-ilk-not-20260320T102700Z.md")
        let dated = MemexMarkdown.filename(c, style: .date)
        XCTAssertTrue(dated.hasSuffix("-k-pr-testi-ilk-not.md"))
        XCTAssertEqual(dated.count, "2026-03-20-13-27-".count + "k-pr-testi-ilk-not.md".count)
        XCTAssertEqual(MemexMarkdown.filename(Capture(title: "x", body: "", day: "2026-03-20"), style: .date), "2026-03-20.md")
    }

    func testWriteDirFromGovernance() {
        XCTAssertEqual(MemexMarkdown.writeDir(governanceYAML: nil), "inbox")
        XCTAssertEqual(MemexMarkdown.writeDir(governanceYAML: "x: 1\nwrite_dir: \"captures/phone\"  # note\n"), "captures/phone")
        XCTAssertEqual(MemexMarkdown.writeDir(governanceYAML: "write_dir:   \n"), "inbox")
    }

    func testPendingBodyMirrorsBookmarklet() {
        let p = PendingCapture(title: "T", url: "https://a.b", text: "one\ntwo")
        XCTAssertEqual(p.body, "> one\n> two\n\nhttps://a.b\n")
    }
}
