import Foundation
import Testing
@testable import SkillboxCore

struct FrontmatterTests {
    @Test func scalarAndMetadata() {
        let fm = FrontmatterParser.parse("---\nname: example\ndescription: \"Use when: needed\"\ntags: [One, Two]\nmetadata:\n  skill-author: K-Dense Inc.\n---\n# Body")
        #expect(fm["name"] == "example")
        #expect(fm["description"] == "Use when: needed")
        #expect(fm.tags == ["One", "Two"])
        #expect(fm.metadata["skill-author"] == "K-Dense Inc.")
        #expect(fm.body == "# Body")
    }
    @Test func foldedAndBlockList() {
        let fm = FrontmatterParser.parse("---\ndescription: >\n  First part\n  second part.\ntags:\n  - One\n  - Two\n---\n")
        #expect(fm["description"] == "First part second part.")
        #expect(fm.tags == ["One", "Two"])
    }
    @Test func missingOrUnterminated() {
        for text in ["# Hello\nBody", "---\nname: test\n"] {
            let fm = FrontmatterParser.parse(text)
            #expect(fm.fields.isEmpty)
            #expect(fm.body == text)
        }
    }
    @Test func windowsLines() {
        let fm = FrontmatterParser.parse("---\r\nname: x\r\ndescription: hello\r\n---\r\nbody\r\n")
        #expect(fm["name"] == "x")
        #expect(fm["description"] == "hello")
    }
}
