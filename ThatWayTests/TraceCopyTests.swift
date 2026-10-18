//
//  TraceCopyTests.swift
//  ThatWayTests
//
//  The rule behind every sentence a person is asked to agree to: never promise one thing and do another. These tests cannot
//  prove a sentence is true, but they stop the ways it quietly stops being true: wording edited without a new version, a
//  promise the app does not keep, a box ticked for the person.
//

import Testing
import Foundation
import ThatWayCore
@testable import ThatWay

struct TraceCopyTests {
    /// Edit a consent sentence and this fails until BOTH the version and the fingerprint below are updated together.
    /// (The server records which version each person agreed to, so a changed sentence under an old version is a lie.)
    @Test func consentWordingIsPinnedToItsVersion() {
        #expect(ConsentCopy.version == "2026-10-18.1")
        #expect(ConsentCopy.fingerprint == "af95931e926f", "the wording changed: bump ConsentCopy.version and update this fingerprint")
    }

    @Test func theConsentNamesTheTracerAndTheEndTime() {
        let all = ConsentCopy.allText
        #expect(all.contains("{name}") && all.contains("{time}"))
        let filled = ConsentCopy.fill(ConsentCopy.tick, name: "sam", time: "3:40 pm")
        #expect(filled.contains("sam") && filled.contains("3:40 pm") && !filled.contains("{"))
    }

    @Test func everyRiskIsInPlainWords() {
        let all = ConsentCopy.allText
        #expect(all.contains("at most once every 2 minutes"), "how often they can look")
        #expect(all.contains("even when ThatWay is in the background") && all.contains("blue location indicator"), "when the phone shares, and that iOS shows it")
        #expect(all.contains("swipe ThatWay away"), "how sharing pauses")
        #expect(all.contains("even if you forget"), "it ends by itself")
        #expect(all.contains("stop it, unfriend"), "how it stops")
        #expect(all.contains("banner"), "that the person will always see it")
        #expect(all.contains("at most every 30 minutes"), "how often they are told")
        #expect(all.contains("never told how long you have allowed"), "what the tracer sees")
        #expect(all.contains("Only allow people you trust"), "the plain warning")
        #expect(all.contains("not an emergency service"), "no pretence of rescue")
        #expect(all.contains("Saying yes is free"), "no hidden cost")
    }

    @Test func nothingPromisesWhatTheAppDoesNotDo() {
        let all = (ConsentCopy.allText + TraceCopy.requestDisclosure.joined() + TraceCopy.deleteWarning + TraceCopy.deactivateWarning).lowercased()
        for promise in ["guarantee", "100%", "always safe", "completely private", "no one will ever", "we will call", "we will send help", "we monitor"] {
            #expect(!all.contains(promise), "“\(promise)” is a promise we cannot keep")
        }
        #expect(!all.contains("exact location"), "a phone may only know roughly where it is")
    }

    @Test func theTracerWordingIsExactlyTheOneGenericAnswer() {
        #expect(TraceCopy.cannotTrace == "User cannot be traced, error has occurred")
        for line in TraceCopy.requestDisclosure where line.contains("only see") { #expect(line.contains(TraceCopy.cannotTrace)) }
    }

    @Test func theRequestSayHowToExpectToBeSeen() {
        let all = TraceCopy.requestDisclosure.joined(separator: " ")
        #expect(all.contains("not be told exactly how long"))
        #expect(all.contains("when you last looked") && all.contains("how far away"))
        #expect(all.contains("every 2 minutes"))
        #expect(TraceCopy.requestIntro(name: "sam").contains("Nothing is shared unless they say yes"))
    }

    @Test func blockingAndDeletingSayWhatReallyHappens() {
        let block = TraceCopy.blockExplanation(name: "sam")
        #expect(block.contains("ends any tracing in both directions") && block.contains("not told") && block.contains("not be friends again"))
        let delete = TraceCopy.deleteWarning
        #expect(delete.contains("can’t be undone") && delete.contains("Apple") && delete.contains("subscription"))
        #expect(delete.contains("Reports") && delete.contains("never contain locations"), "the one thing that is kept is said")
        let deactivate = TraceCopy.deactivateWarning
        #expect(deactivate.contains("12 months") && deactivate.contains("will not be restored"))
    }

    @Test func theEmergencyControlIsHonestAboutWhatItIs() {
        #expect(TraceCopy.emergencyDisclosure.contains("not an emergency service"))
        #expect(TraceCopy.emergencyDisclosure.contains("only opens your phone’s dialler"))
        #expect(TraceCopy.reportDisclosure.contains("can’t promise a reply time"))
    }

    @Test func theKindChoicesDescribeWhatEachDoes() {
        #expect(TraceCopy.kindExplanation(.once, name: "sam").contains("sam switches to someone else"))
        #expect(TraceCopy.kindExplanation(.keep, name: "sam").contains("while sam looks at other friends"))
    }
}
