import Testing
import Foundation
import BatteryCore
@testable import BatteryPlatform

struct ControlChannelTests {
    /// Unix socket paths must stay under 104 bytes.
    func path() -> URL { URL(fileURLWithPath:"/tmp/vb-\(UUID().uuidString.prefix(8)).sock") }
    let queue=DispatchQueue(label:"control-tests")
    func server(_ p:URL,_ handler:@escaping (ChargeCommand)->ControlResponse) throws -> ControlServer {
        let s=ControlServer(path:p,handler:handler,queue:queue);try s.start();return s
    }

    @Test func requestParsing() {
        #expect(ControlRequest(command:"setLimit",value:70).chargeCommand() == .setLimit(70))
        #expect(ControlRequest(command:"setLimit",value:73).chargeCommand()==nil)
        #expect(ControlRequest(command:"setLimit",value:45).chargeCommand()==nil)
        #expect(ControlRequest(command:"setLimit",value:nil).chargeCommand()==nil)
        #expect(ControlRequest(command:"reboot",value:nil).chargeCommand()==nil)
        #expect(ControlRequest(command:"clearLimit",value:nil).chargeCommand() == .clearLimit)
        #expect(ControlRequest(command:"startTopUp",value:nil).chargeCommand() == .startTopUp)
        #expect(ControlRequest(command:"endTopUp",value:nil).chargeCommand() == .endTopUp)
        #expect(ControlRequest(.setLimit(75)) == ControlRequest(command:"setLimit",value:75))
    }
    @Test func roundTripCallsHandler() throws {
        let p=path();var got:[ChargeCommand]=[]
        let s=try server(p) { got.append($0);return ControlResponse(ok:true,message:"적용을 확인했습니다. 현재 상한 75%",state:ChargeLimitState(supported:true,enabled:true,limit:75)) }
        defer { s.stop() }
        let r=try ControlClient.send(ControlRequest(.setLimit(75)),path:p)
        #expect(r.ok);#expect(r.state?.limit==75);#expect(got==[.setLimit(75)])
    }
    @Test func unknownCommandRejectedWithoutHandler() throws {
        let p=path();var calls=0
        let s=try server(p) { _ in calls+=1;return ControlResponse(ok:true,message:"",state:nil) };defer { s.stop() }
        let r=try ControlClient.send(ControlRequest(command:"reboot",value:nil),path:p)
        #expect(!r.ok);#expect(r.message=="지원하지 않는 요청입니다.");#expect(calls==0)
    }
    @Test func oversizedLineRejected() throws {
        let p=path();var calls=0
        let s=try server(p) { _ in calls+=1;return ControlResponse(ok:true,message:"",state:nil) };defer { s.stop() }
        let r=try ControlClient.exchange(Data(repeating:UInt8(ascii:"a"),count:2000)+Data("\n".utf8),path:p,connectTimeout:5,responseTimeout:5)
        #expect(!r.ok);#expect(calls==0)
    }
    @Test func missingSocketIsNotRunning() {
        #expect(throws:ControlClient.Failure.notRunning) { try ControlClient.send(ControlRequest(.clearLimit),path:path()) }
    }
    @Test func slowHandlerTimesOut() throws {
        let p=path()
        let s=try server(p) { _ in Thread.sleep(forTimeInterval:2);return ControlResponse(ok:true,message:"",state:nil) };defer { s.stop() }
        #expect(throws:ControlClient.Failure.timedOut) { try ControlClient.send(ControlRequest(.clearLimit),path:p,responseTimeout:0.5) }
    }
    @Test func serverReplacesStaleSocket() throws {
        let p=path();FileManager.default.createFile(atPath:p.path,contents:Data("stale".utf8))
        let s=try server(p) { _ in ControlResponse(ok:true,message:"ok",state:nil) };defer { s.stop() }
        #expect(try ControlClient.send(ControlRequest(.endTopUp),path:p).ok)
    }
    @Test func socketIsPrivate() throws {
        let p=path();let s=try server(p) { _ in ControlResponse(ok:true,message:"",state:nil) };defer { s.stop() }
        let mode=try FileManager.default.attributesOfItem(atPath:p.path)[.posixPermissions] as? Int
        #expect(mode==0o600)
    }
    /// `vbctl charge status` only checks that the app listens and hangs up; answering it must not kill the app with SIGPIPE.
    @Test func hangUpWithoutRequestKeepsServing() throws {
        let p=path()
        let s=try server(p) { _ in ControlResponse(ok:true,message:"ok",state:nil) };defer { s.stop() }
        #expect(ControlClient.isListening(path:p))
        Thread.sleep(forTimeInterval:0.3)
        #expect(ControlClient.isListening(path:p))
        #expect(try ControlClient.send(ControlRequest(.endTopUp),path:p).ok)
    }
    @Test func stopRemovesSocket() throws {
        let p=path();let s=try server(p) { _ in ControlResponse(ok:true,message:"",state:nil) }
        s.stop()
        #expect(!FileManager.default.fileExists(atPath:p.path))
        #expect(throws:ControlClient.Failure.notRunning) { try ControlClient.send(ControlRequest(.clearLimit),path:p) }
    }
}
