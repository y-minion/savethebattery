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
}
