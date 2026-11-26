import Foundation
@testable import Ombre
import Testing
import WebKit

/// The selectors the element picker writes (`ElementPickerScript`), in a
/// real page of a hidden web view: each finds its element alone, without
/// the classes and identifiers frameworks generate.
@MainActor
struct ElementPickerSelectorTests {
    /// The selector for the element marked `data-target`, and whether it
    /// finds that element alone.
    private func selector(in body: String) async throws -> String {
        let page = try await OffscreenPage(body)
        let value = try await page.run("""
        const target = document.querySelector("[data-target]");
        const selector = picker.selectorFor(target);
        const found = document.querySelectorAll(selector);
        return { selector: selector, unique: found.length === 1 && found[0] === target };
        """)
        let result = try #require(value as? [String: Any])
        let selector = try #require(result["selector"] as? String)
        #expect(result["unique"] as? Bool == true, "\(selector) must find the element alone")
        return selector
    }

    @Test func aStableIdentifierIsEnough() async throws {
        let selector = try await selector(in: #"<main><div id="sidebar" data-target>x</div></main>"#)
        #expect(selector == "#sidebar")
    }

    @Test func generatedIdentifiersAndClassesAreNeverUsed() async throws {
        let selector = try await selector(in: """
        <div class="layout">
          <section id="ember1234" data-target
            class="css-1x2y3z sc-AbCdE Header_title__aB3dE jsx-293847 active">a</section>
          <section class="css-9q8w7e">b</section>
        </div>
        """)
        for generated in ["ember1234", "css-", "sc-AbCdE", "Header_title__aB3dE", "jsx-", "active"] {
            #expect(!selector.contains(generated), "\(selector) contains \(generated)")
        }
        #expect(selector.hasSuffix("section:nth-of-type(1)"))
    }

    @Test func attributesComeBeforeClasses() async throws {
        let selector = try await selector(in: """
        <div class="panel" data-testid="weather" data-target>a</div><div class="panel">b</div>
        """)
        #expect(selector == #"div[data-testid="weather"]"#)
    }

    /// Words with a number ("3 notifications") change: never in a selector.
    @Test func labelsWithNumbersAreNotUsed() async throws {
        let selector = try await selector(in: """
        <nav id="top"><button aria-label="3 notifications" data-target>a</button><button>b</button></nav>
        """)
        #expect(!selector.contains("notifications"))
        #expect(selector.hasSuffix("button:nth-of-type(1)"))
    }

    /// Dashboard panels alike (Grafana): told apart by their stable key.
    @Test func dashboardPanelsByTheirKey() async throws {
        let selector = try await selector(in: """
        <div class="react-grid-layout">
          <div class="react-grid-item" data-viz-panel-key="panel-1">cpu</div>
          <div class="react-grid-item" data-viz-panel-key="panel-2" data-target>memory</div>
        </div>
        """)
        #expect(selector == #"div[data-viz-panel-key="panel-2"]"#)
    }

    /// Siblings alike: the structure, from the nearest stable identifier.
    @Test func repeatedSiblingsByPositionUnderAStableAncestor() async throws {
        let selector = try await selector(in: """
        <ul id="news"><li class="item">1</li><li class="item" data-target>2</li><li class="item">3</li></ul>
        <ul><li class="item">4</li><li class="item">5</li></ul>
        """)
        #expect(selector == "#news > li.item:nth-of-type(2)")
    }

    @Test func stableAndGeneratedTokens() async throws {
        let page = try await OffscreenPage("<p>x</p>")
        let value = try await page.run("""
        const stable = ["sidebar", "main-content", "nav_bar", "col-2", "MuiButton-root", "article"];
        const generated = ["css-1x2y3z", "sc-AbCdE", "ember123", ":r1:", "a1B2c", "Header_title__aB3dE",
                           "jsx-2938476", "is-active", "open", "_3fG7h", "kQzPfEwX", "d41d8cd98f"];
        return {
            stable: stable.filter(token => !picker.isStableToken(token, false)),
            generated: generated.filter(token => picker.isStableToken(token, false)),
            identifier: picker.isStableToken("react-select-2-input", true)
        };
        """)
        let result = try #require(value as? [String: Any])
        #expect(result["stable"] as? [String] == [], "refused although stable")
        #expect(result["generated"] as? [String] == [], "kept although generated")
        // A counter in an identifier changes from one visit to the next.
        #expect(result["identifier"] as? Bool == false)
    }

    /// ↑ widens to the parent, ↓ narrows back; an inline element starts at its block.
    @Test func widenAndNarrowFollowTheParents() async throws {
        let page = try await OffscreenPage("""
        <div id="outer"><div id="inner"><p id="text">Some <b data-target>bold</b> words</p></div></div>
        """)
        let value = try await page.run("""
        const labels = [];
        labels.push(picker.start(document.querySelector("[data-target]"))?.label);
        labels.push(picker.widen()?.label);
        labels.push(picker.widen()?.label);
        labels.push(picker.widen()?.label);
        labels.push(picker.narrow()?.label);
        return labels;
        """)
        // Starts at the paragraph: the bold word is inline.
        #expect(value as? [String] == ["p#text", "div#inner", "div#outer", "div#outer", "div#inner"])
    }

    @Test func hideHidesEveryMatchOnThePage() async throws {
        let page = try await OffscreenPage(#"<div class="ad">a</div><div class="ad">b</div><div>c</div>"#)
        let value = try await page.run("""
        const count = picker.hide("div.ad");
        const shown = Array.from(document.querySelectorAll("div"))
            .filter(element => getComputedStyle(element).display !== "none").length;
        return [count, shown];
        """)
        #expect(value as? [Int] == [2, 1])
    }
}
