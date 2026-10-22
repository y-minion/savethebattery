import Testing
import Foundation
import BatteryCore
@testable import BatteryPlatform

struct ChargeCLITests {
    @Test func parsesEachCommand() throws {
        #expect(try ChargeCLI.parse(["set","70"]).get() == .request(ControlRequest(.setLimit(70))))
        #expect(try ChargeCLI.parse(["off"]).get() == .request(ControlRequest(.clearLimit)))
        #expect(try ChargeCLI.parse(["topup"]).get() == .request(ControlRequest(.startTopUp)))
        #expect(try ChargeCLI.parse(["end"]).get() == .request(ControlRequest(.endTopUp)))
        #expect(try ChargeCLI.parse(["status"]).get() == .status(json:false))
        #expect(try ChargeCLI.parse(["status","--json"]).get() == .status(json:true))
    }
    @Test func rejectsBadInput() {
        for args in [["set","73"],["set","40"],["set","abc"],["set"],[],["reboot"],["set","70","80"]] {
            guard case .failure(let usage)=ChargeCLI.parse(args) else { Issue.record("accepted \(args)");continue }
            #expect(usage.text.contains("vbctl charge set <50-100>"))
        }
    }
    @Test func exitCodes() {
        #expect(ChargeCLI.exitCode(.success(ControlResponse(ok:true,message:"",state:nil)))==0)
        #expect(ChargeCLI.exitCode(.failure(.timedOut))==1)
        #expect(ChargeCLI.exitCode(.failure(.notRunning))==3)
        #expect(ChargeCLI.message(.failure(.notRunning))=="VibeBattery 앱이 실행 중이어야 합니다. 앱을 열고 다시 시도하세요.")
        #expect(ChargeCLI.message(.failure(.timedOut))=="결과를 확인하지 못했습니다. vbctl charge status로 확인하세요")
    }
    @Test func blockedRequestMapsToFailureExit() {
        let r=ControlResponse(ok:false,message:"AlDente이(가) 충전을 관리하고 있어 VibeBattery는 값을 바꾸지 않습니다.",state:nil)
        #expect(ChargeCLI.exitCode(.success(r))==1);#expect(ChargeCLI.message(.success(r))==r.message)
    }
    func keys(_ r:ChargeStatusReport) throws -> Set<String> {
        Set((try JSONSerialization.jsonObject(with:try JSONEncoder().encode(r)) as? [String:Any])?.keys ?? [:].keys)
    }
    @Test func statusReportKeepsOldKeys() throws {
        var rec=ChargeRecord();rec.lastWritten=70
        let r=ChargeStatusReport.make(state:ChargeLimitState(supported:true,enabled:true,limit:70),record:rec,rules:[],appRunning:true,now:Date(),calendar:.current)
        #expect(try keys(r).isSuperset(of:["supported","enabled","limit","origin","topUpActive"]))
        #expect(r.origin=="vibeBattery");#expect(!r.topUpActive)
    }
    @Test func nextScheduleOnlyWhenAppRuns() {
        let rules=[ChargeScheduleTests.rule(22)],now=ChargeScheduleTests.at(10,22,21,0),cal=ChargeScheduleTests.calendar()
        let s=ChargeLimitState(supported:true,enabled:true,limit:70)
        #expect(ChargeStatusReport.make(state:s,record:nil,rules:rules,appRunning:true,now:now,calendar:cal).nextSchedule==ChargeScheduleTests.at(10,22,22,0))
        #expect(ChargeStatusReport.make(state:s,record:nil,rules:rules,appRunning:false,now:now,calendar:cal).nextSchedule==nil)
    }
}
