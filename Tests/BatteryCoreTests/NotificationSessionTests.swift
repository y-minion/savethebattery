import Testing
import Foundation
@testable import BatteryCore
struct NotificationSessionTests {
    let id=UUID()
    func s(_ dt:Double,_ outcome:SessionOutcome = .running,ended:Double?=nil,code:Int32?=nil,released:Bool=false) -> NotificationInput {
        var i=NT.input(dt)
        i.sessions=[SessionSummary(id:id,command:"claude",outcome:outcome,started:NT.t0-3600,ended:ended.map { NT.t0+$0 },exitCode:code,released:released)]
        return i
    }
    var end:String { "session.end.\(id.uuidString)" }
    @Test func endAfterSeenRunningShowsResultAndDuration() {
        let r=NT.run([s(0),s(30,.succeeded,ended:20,code:0)])
        #expect(NT.ids(r)==[[],[end]])
        let e=r[1].events[0];#expect(e.title=="claude 완료");#expect(e.body=="걸린 시간 1시간");#expect(e.section=="sessions");#expect(e.thread=="session")
        #expect(NT.run([s(0),s(30,.failed,ended:20,code:2)])[1].events[0].title=="claude 실패 · 코드 2")
    }
    @Test func protectionReleaseIsAnnouncedThenEndStillArrives() {
        let r=NT.run([s(0),s(30,.detached),s(60,.detached),s(90,.detached,ended:80,code:0)])
        #expect(NT.ids(r)==[[],["session.released.\(id.uuidString)"],[],[end]])
        #expect(r[1].events[0].body.contains("어댑터"));#expect(r[3].events[0].title=="claude 보호 해제 후 종료 · 코드 0")
        #expect(NT.run([s(0),s(30,.expired)])[1].events[0].body.contains("보호 시간"))
    }
    @Test func userReleaseIsNotAnnounced() {
        #expect(NT.ids(NT.run([s(0),s(30,.detached,released:true)]))==[[],[]])
    }
    @Test func cancelledFollowsItsOwnToggle() {
        let steps=[s(0),s(30,.cancelled,ended:20,code:130)]
        #expect(NT.ids(NT.run(steps))[1]==[end]);#expect(NT.run(steps)[1].events[0].title=="claude 취소됨")
        var off=NT.all;off.sessionCancelled=false
        #expect(NT.ids(NT.run(steps,off))[1]==[])
    }
    @Test func sessionsFirstSeenAfterEndingAreAnnouncedOnlyIfRecent() {
        #expect(NT.ids(NT.run([s(0,.succeeded,ended:-300,code:0)]))==[[end]])
        #expect(NT.ids(NT.run([s(0,.succeeded,ended:-1200,code:0)]))==[[]])
        // Already released before the app saw it.
        #expect(NT.ids(NT.run([s(0,.detached),s(30,.detached)]))==[[],[]])
    }
    @Test func moreThanThreeEndingsAreBatched() {
        var a=NT.input(0),b=NT.input(30)
        for _ in 0..<4 {
            let u=UUID()
            a.sessions.append(SessionSummary(id:u,command:"codex",outcome:.running,started:NT.t0-60))
            b.sessions.append(SessionSummary(id:u,command:"codex",outcome:.succeeded,started:NT.t0-60,ended:NT.t0+10,exitCode:0))
        }
        let r=NT.run([a,b]);#expect(NT.ids(r)==[[],["session.batch"]]);#expect(r[1].events[0].title=="작업 4개 종료")
        #expect(r[1].events[0].body=="성공 4 · 그 외 0")
    }
    @Test func memoryKeepsOnlyListedSessions() {
        let r=NT.run([s(0),NT.input(30)])
        #expect(r[0].memory.sessions[id.uuidString] != nil);#expect(r[1].memory.sessions.isEmpty)
    }
}
