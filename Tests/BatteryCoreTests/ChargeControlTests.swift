import Testing
import Foundation
@testable import BatteryCore
struct ChargeControlTests {
    func hot(_ t:Double?,percent:Int=85,at now:Date) -> BatterySnapshot {
        var b=BatterySnapshot();b.timestamp=now;b.temperature=t;b.percent=percent;b.onAC=true;b.charging=true;return b
    }
    let on:HeatSettings={ var s=HeatSettings();s.enabled=true;return s }()
    let limit90=ChargeLimitState(supported:true,enabled:true,limit:90)
    @Test func commandRangeAndHelperRouting() {
        #expect(ChargeCommand.setLimit(50).isValid);#expect(ChargeCommand.setLimit(100).isValid)
        #expect(!ChargeCommand.setLimit(49).isValid);#expect(!ChargeCommand.setLimit(101).isValid)
        #expect(ChargeCommand.setLimit(75).requiresHelper);#expect(!ChargeCommand.setLimit(80).requiresHelper)
        #expect(!ChargeCommand.startTopUp.requiresHelper);#expect(ChargeCommand.clearLimit.isValid)
        // macOS offers 5% steps; other values are unverified for the private setter.
        #expect(!ChargeCommand.setLimit(79).isValid);#expect(!ChargeCommand.setLimit(83).isValid);#expect(ChargeCommand.setLimit(75).requiresHelper)
    }
    @Test func originDistinguishesOwnExternalAndUnknown() {
        #expect(ChargeLimitState(supported:true,enabled:true,limit:79).origin(lastWritten:nil) == .external)
        #expect(ChargeLimitState(supported:true,enabled:true,limit:80).origin(lastWritten:80) == .vibeBattery)
        #expect(ChargeLimitState(supported:true,enabled:false,limit:80).origin(lastWritten:80) == LimitOrigin.none)
        #expect(ChargeLimitState().origin(lastWritten:80) == .unknown)
        #expect(ChargeLimitState(supported:false,enabled:true,limit:80).origin(lastWritten:80) == .unknown)
    }
    @Test func readbackMatchingPerCommand() {
        let s=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(s.matches(.setLimit(85))==true);#expect(s.matches(.setLimit(80))==false)
        #expect(s.matches(.clearLimit)==false);#expect(s.matches(.endTopUp)==true);#expect(s.matches(.startTopUp)==nil)
    }
    @Test func heatSettingsRejectInvertedOrNonFiniteThresholds() {
        var s=HeatSettings();s.holdAt = .nan;s.resumeAt = .infinity;s.validate()
        #expect(s.holdAt==35);#expect(s.resumeAt==32)
        s.holdAt=31;s.resumeAt=33;s.validate();#expect(s.resumeAt==30)
    }
    @Test func holdsAtCurrentChargeAndResumesAfterStableCooling() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(36,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0) == .hold(85))
        let held=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+60),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+60) == HeatAction.none)
        #expect(HeatHoldPolicy.step(snapshot:hot(33,at:t0+120),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+120) == HeatAction.none)
        #expect(st.coolSince==nil)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+180),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+180) == HeatAction.none)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+420),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+420) == HeatAction.none)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+480),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+480) == .restore(.setLimit(90)))
        #expect(st==HeatState())
    }
    @Test func externalChangeDuringHoldIsNeverOverwritten() {
        let t0=Date();var st=HeatState()
        _=HeatHoldPolicy.step(snapshot:hot(36,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0)
        let changed=ChargeLimitState(supported:true,enabled:true,limit:95)
        #expect(HeatHoldPolicy.step(snapshot:hot(36,at:t0+30),limit:changed,settings:on,state:&st,helperAvailable:false,now:t0+30) == .yielded)
        #expect(st==HeatState())
    }
    @Test func holdRoundsUpToSupportedStepAndSkipsWhenLimitIsNear() {
        let t0=Date();var st=HeatState()
        let limit100=ChargeLimitState(supported:true,enabled:true,limit:100)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:87,at:t0),limit:limit100,settings:on,state:&st,helperAvailable:false,now:t0) == .hold(90))
        st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:87,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0) == HeatAction.none)
        #expect(st==HeatState())
    }
    @Test func staleOrMissingTemperatureNeverHoldsOrResumes() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(nil,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .sensorUnavailable)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0-121),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .sensorUnavailable)
        st.holdLimit=85;st.userLimit=90;st.coolSince=t0-1000
        let held=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(HeatHoldPolicy.step(snapshot:hot(20,at:t0-500),limit:held,settings:on,state:&st,helperAvailable:true,now:t0) == .sensorUnavailable)
        #expect(st.holdLimit==85);#expect(st.coolSince==nil)
    }
    @Test func lowChargeOrMissingHelperOnlyWarns() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:45,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .cannotHold(.lowCharge))
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:70,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0) == .cannotHold(.needsHelper))
        #expect(st==HeatState())
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:70,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .hold(70))
        #expect(st.holdLimit==70);#expect(st.userLimit==90)
    }
    @Test func unknownLimitOrDisabledFeatureNeverHolds() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0),limit:ChargeLimitState(),settings:on,state:&st,helperAvailable:true,now:t0) == .cannotHold(.limitUnknown))
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0),limit:limit90,settings:HeatSettings(),state:&st,helperAvailable:true,now:t0) == HeatAction.none)
        var idle=hot(40,at:t0);idle.charging=false
        #expect(HeatHoldPolicy.step(snapshot:idle,limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == HeatAction.none)
        #expect(st==HeatState())
    }
    @Test func disablingDuringHoldRestoresNoLimitWhenNoneExisted() {
        let t0=Date();var st=HeatState()
        let none=ChargeLimitState(supported:true,enabled:false,limit:nil)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0),limit:none,settings:on,state:&st,helperAvailable:false,now:t0) == .hold(85))
        let held=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0+30),limit:held,settings:HeatSettings(),state:&st,helperAvailable:false,now:t0+30) == .restore(.clearLimit))
    }
}
