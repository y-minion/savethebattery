import Foundation
public enum NotificationPolicy {
    /// Longer than this since the last evaluation (sleep, app closed) and change-based checks restart from a baseline.
    public static let gap:TimeInterval=300
    public static let offACRearm:TimeInterval=300, onACRearm:TimeInterval=120
    public static func evaluate(_ i:NotificationInput,settings s:NotificationSettings,memory:NotificationMemory) -> NotificationOutcome {
        var o=NotificationOutcome(memory:memory)
        o.memory.clamp(i.now)
        let continuous=o.memory.evaluated.map { i.now.timeIntervalSince($0)<=gap } ?? false
        charge(i,s,&o,continuous:continuous)
        protect(i,s,&o);heat(i,s,&o)
        sessions(i,s,&o)
        o.memory.evaluated=i.now
        return o
    }
    static func charge(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome,continuous:Bool) {
        let b=i.battery,now=i.now
        if let off=o.memory.offACSince,now.timeIntervalSince(off)>offACRearm { o.memory.limitNotified=nil }
        let steadyAC=b.onAC && (o.memory.onACSince.map { now.timeIntervalSince($0)>=onACRearm } ?? false)
        if b.onAC { o.memory.offACSince=nil;if o.memory.onACSince==nil { o.memory.onACSince=now } }
        else { o.memory.onACSince=nil;if o.memory.offACSince==nil { o.memory.offACSince=now } }
        if let n=o.memory.limitNotified,i.limit.enabled != true || i.limit.limit != n { o.memory.limitNotified=nil }
        if let p=b.percent {
            // Charging just stopped at the limit; the displayed percent is rounded, so one point short counts.
            if continuous,o.memory.wasCharging==true,b.onAC,!b.charging,i.limit.enabled==true,let l=i.limit.limit,p>=l-1,
               !i.heatHolding,i.topUpRequested==nil,o.memory.limitNotified==nil {
                o.memory.limitNotified=l
                let t=NotificationText.limitReached(l)
                o.send(s.limitReached,AlertEvent(id:"charge.limitReached",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
            if let r=i.topUpRequested,b.onAC,p>=99,o.memory.topUpNotified != r {
                o.memory.topUpNotified=r
                let t=NotificationText.topUpDone(p)
                o.send(s.topUpDone,AlertEvent(id:"charge.topUpDone",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
            if !o.memory.lowArmed,p>=s.lowAt+5 || steadyAC { o.memory.lowArmed=true;o.remove("charge.low") }
            if o.memory.lowArmed,!b.onAC,p<=s.lowAt {
                o.memory.lowArmed=false
                let t=NotificationText.lowBattery(p,at:s.lowAt)
                o.send(s.lowBattery,AlertEvent(id:"charge.low",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
        }
        o.memory.wasCharging=b.charging
        let origin=i.limit.origin(lastWritten:i.lastWritten)
        if origin != .unknown {
            // Only a change VibeBattery did not write itself: its own writes move `lastWritten`, and top-up and a yielded hold explain themselves.
            if o.memory.origin == .vibeBattery,origin == .external || origin == .none,o.memory.lastWritten==i.lastWritten,
               i.topUpRequested==nil,i.heatEvent != .yielded {
                let t=NotificationText.limitChanged(origin == .none ? nil:i.limit.limit)
                o.send(s.limitChanged,AlertEvent(id:"charge.limitChanged",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
            if origin == .vibeBattery,let before=o.memory.origin,before != .vibeBattery { o.remove("charge.limitChanged") }
            o.memory.origin=origin;o.memory.lastWritten=i.lastWritten
        }
        if i.limit.supported==true {
            if o.memory.unavailableNotified { o.remove("charge.unavailable") }
            o.memory.supportedSeen=true;o.memory.unavailableNotified=false
        } else if i.limit.supported==false,o.memory.supportedSeen,!o.memory.unavailableNotified {
            o.memory.unavailableNotified=true
            let t=NotificationText.controlUnavailable
            o.send(s.controlUnavailable,AlertEvent(id:"charge.unavailable",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
        }
    }
    public static let hotCooldown:TimeInterval=1800, hotRearm=3.0, onBatteryExtra=2.0, freshTemperature:TimeInterval=120
    public static let stuckRepeat:TimeInterval=86400, sensorDelay:TimeInterval=600
    static func protect(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        let b=i.battery,now=i.now,age=now.timeIntervalSince(b.timestamp)
        if b.percent != nil,let t=b.temperature,age >= -5,age<=freshTemperature {
            let limit=b.onAC ? s.hotAt:s.hotAt+onBatteryExtra
            if !o.memory.hotArmed,t<=limit-hotRearm { o.memory.hotArmed=true;o.remove("protect.heat") }
            if o.memory.hotArmed,t>=limit,o.memory.hotSent.map({ now.timeIntervalSince($0)>=hotCooldown }) ?? true {
                o.memory.hotArmed=false;o.memory.hotSent=now
                let x=NotificationText.hot(t,onAC:b.onAC)
                o.send(s.highTemperature,AlertEvent(id:"protect.heat",title:x.0,body:x.1,section:"settings",thread:"protect"))
            }
        }
        let names=Array(Set(i.conflicts)).sorted()
        if names.isEmpty {
            if !o.memory.conflicts.isEmpty { o.remove("protect.conflict") }
        } else if names.contains(where:{ !o.memory.conflicts.contains($0) }) {
            let x=NotificationText.conflict(names)
            o.send(s.conflict,AlertEvent(id:"protect.conflict",title:x.0,body:x.1,section:"dashboard",thread:"protect"))
        }
        o.memory.conflicts=names
    }
    static func heat(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        let now=i.now
        if let l=i.heatStuckLimit {
            if o.memory.stuckSent.map({ now.timeIntervalSince($0)>=stuckRepeat }) ?? true {
                o.memory.stuckSent=now
                let x=NotificationText.heatStuck(l)
                o.send(s.heatProblem,AlertEvent(id:"heat.stuck",title:x.0,body:x.1,section:"settings",thread:"protect"))
            }
        } else if o.memory.stuckSent != nil { o.memory.stuckSent=nil;o.remove("heat.stuck") }
        switch i.heatEvent {
        case .yielded?:
            let x=NotificationText.heatPaused
            o.send(s.heatProblem,AlertEvent(id:"heat.paused",title:x.0,body:x.1,section:"settings",thread:"protect",duplicatesAppMessage:true))
        case .holdFailed?:
            let x=NotificationText.heatFailed
            o.send(s.heatProblem,AlertEvent(id:"heat.failed",title:x.0,body:x.1,section:"settings",thread:"protect",duplicatesAppMessage:true))
        case .held(let p)?:
            let x=NotificationText.heatHeld(p)
            o.send(s.heatActivity,AlertEvent(id:"heat.activity",title:x.0,body:x.1,section:"settings",thread:"protect"))
        case .restored?:
            let x=NotificationText.heatRestored
            o.send(s.heatActivity,AlertEvent(id:"heat.activity",title:x.0,body:x.1,section:"settings",thread:"protect"))
        case nil:break
        }
        if i.heatSensorMissing {
            let since=o.memory.sensorMissingSince ?? now;o.memory.sensorMissingSince=since
            if !o.memory.sensorNotified,now.timeIntervalSince(since)>=sensorDelay {
                o.memory.sensorNotified=true
                let x=NotificationText.heatSensor
                o.send(s.heatProblem,AlertEvent(id:"heat.sensor",title:x.0,body:x.1,section:"settings",thread:"protect"))
            }
        } else {
            if o.memory.sensorNotified { o.remove("heat.sensor") }
            o.memory.sensorMissingSince=nil;o.memory.sensorNotified=false
        }
    }
    public static let lateSession:TimeInterval=600, batchLimit=3
    static func sessions(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        var ended:[SessionSummary]=[],marks:[String:SessionMark]=[:]
        for x in i.sessions {
            let key=x.id.uuidString
            guard var m=o.memory.sessions[key] else {
                // First sight: only a recent ending is news; an already released protection is not.
                if let e=x.ended {
                    let age=i.now.timeIntervalSince(e)
                    if age>=0,age<=lateSession { ended.append(x) }
                    marks[key]=SessionMark(ended:true,released:true)
                } else { marks[key]=SessionMark(released:x.outcome != .running) }
                continue
            }
            if x.ended==nil,!m.released,x.outcome != .running {
                m.released=true
                if x.outcome == .expired || (x.outcome == .detached && !x.released) {
                    let t=NotificationText.protectionReleased(x)
                    o.send(s.protectionReleased,AlertEvent(id:"session.released.\(key)",title:t.0,body:t.1,section:"sessions",thread:"session"))
                }
            }
            if x.ended != nil,!m.ended { m.ended=true;m.released=true;ended.append(x) }
            marks[key]=m
        }
        o.memory.sessions=marks
        let wanted=ended.filter { $0.outcome == .cancelled ? s.sessionCancelled:s.sessionEnded }
        if wanted.count>batchLimit {
            let t=NotificationText.sessionBatch(wanted)
            o.send(true,AlertEvent(id:"session.batch",title:t.0,body:t.1,section:"sessions",thread:"session"))
        } else {
            for x in wanted {
                let t=NotificationText.sessionEnd(x)
                o.send(true,AlertEvent(id:"session.end.\(x.id.uuidString)",title:t.0,body:t.1,section:"sessions",thread:"session"))
            }
        }
    }
}
