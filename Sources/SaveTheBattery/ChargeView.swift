import SwiftUI
import BatteryCore
import BatteryPlatform
/// Everything that changes charging lives here; other pages only show status and link to it.
struct ChargeView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        PageTitle(title:tr("Charge","충전"),subtitle:tr("Manage the limit, one-time top-up and schedules in one place.","상한, 한 번 완충, 일정을 한 곳에서 관리하세요."))
        ChargeControlCard()
        ScheduleCard()
        HeatCard()
        HelperLogCard()
    }
}
struct ScheduleCard:View {
    @EnvironmentObject var model:AppModel
    @State private var editing:ChargeScheduleRule?
    @State private var adding=false
    var rules:[ChargeScheduleRule] { model.preferences.schedules }
    var full:Bool { rules.count>=SchedulePolicy.maxRules }
    func next(_ r:ChargeScheduleRule) -> String? {
        let now=Date()
        return SchedulePolicy.next(r,after:max(now,r.activeSince),calendar:.current).map { tr("Next: ","다음: ")+ScheduleText.when($0,now:now,calendar:.current) }
    }
    var body:some View {
        Card {
            HStack {
                Label(tr("Schedules","일정"),systemImage:"calendar.badge.clock").font(.headline);Spacer()
                Button { adding=true } label: { Label(tr("Add schedule","일정 추가"),systemImage:"plus") }.disabled(full)
            }
            if rules.isEmpty {
                Text(tr("No schedules yet. Tap a common one to add it.","아직 일정이 없어요. 자주 쓰는 일정을 눌러 바로 추가하세요.")).foregroundStyle(.secondary)
                ForEach(ChargeScheduleRule.templates(now:Date())) { t in
                    Button { model.addSchedule(t) } label: {
                        HStack { VStack(alignment:.leading,spacing:2) { Text(t.name).font(.body.weight(.medium));Text(ScheduleText.sentence(t)).font(.caption).foregroundStyle(.secondary) };Spacer();Image(systemName:"plus.circle.fill").foregroundStyle(.mint) }
                            .padding(10).background(Color.mint.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain)
                }
            } else {
                ForEach(rules) { r in
                    HStack(spacing:12) {
                        Button { editing=r } label: {
                            VStack(alignment:.leading,spacing:2) {
                                Text(r.name).font(.body.weight(.medium))
                                Text(ScheduleText.sentence(r)).font(.callout).foregroundStyle(.secondary)
                                if r.enabled,let n=next(r) { Text(n).font(.caption).foregroundStyle(.tertiary) }
                            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Toggle("",isOn:Binding(get:{ r.enabled },set:{ var c=r;c.enabled=$0;model.updateSchedule(c) })).labelsHidden().toggleStyle(.switch)
                    }
                    .contextMenu { Button(tr("Delete","삭제"),role:.destructive) { model.removeSchedule(id:r.id) } }
                    if r.id != rules.last?.id { Divider() }
                }
            }
            if !model.scheduleRuns.isEmpty {
                DisclosureGroup(tr("Recent runs","최근 실행")) {
                    VStack(alignment:.leading,spacing:6) {
                        ForEach(Array(model.scheduleRuns.reversed().enumerated()),id:\.offset) { _,run in
                            Text("\(ScheduleText.when(run.date,now:Date(),calendar:.current)) · \(run.ruleName) · \(run.action) · \(result(run.result))")
                                .font(.caption).foregroundStyle(run.result == .ran ? Color.secondary:Color.orange)
                        }
                    }.padding(.top,6)
                }
            }
            Text(tr("Works while the app is running. A schedule missed while the Mac slept runs on wake if it is within 12 hours.","앱이 실행 중일 때 동작합니다. 맥이 잠들어 놓친 일정은 12시간 안이면 깨어날 때 실행합니다.")).font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented:$adding) { ScheduleEditor(rule:nil,others:rules) { model.addSchedule($0) } }
        .sheet(item:$editing) { r in ScheduleEditor(rule:r,others:rules.filter { $0.id != r.id },onSave:{ model.updateSchedule($0) },onDelete:{ model.removeSchedule(id:r.id) }) }
    }
    func result(_ r:ScheduleRun.Result) -> String {
        switch r {
        case .ran:return tr("Ran","실행됨")
        case .failed(let m):return tr("Failed: \(m)","실패: \(m)")
        case .skipped:return tr("Skipped (over 12 hours ago)","건너뜀 (12시간 지남)")
        }
    }
}
struct ScheduleEditor:View {
    enum Kind:CaseIterable {
        case limit,topUp,off
        var title:String { switch self { case .limit:return tr("Set limit","상한 정하기");case .topUp:return tr("Top up once","한 번 완충");case .off:return tr("Turn off limit","상한 끄기") } }
    }
    let rule:ChargeScheduleRule?
    let others:[ChargeScheduleRule]
    var onSave:(ChargeScheduleRule)->Void
    var onDelete:(()->Void)?=nil
    @Environment(\.dismiss) private var dismiss
    @State private var days:Set<Int>=Set(1...7)
    @State private var time=Calendar.current.date(from:DateComponents(hour:22,minute:0)) ?? Date()
    @State private var kind=Kind.limit
    @State private var limit=70
    @State private var name=""
    @State private var nameEdited=false
    private let dayOrder=[2,3,4,5,6,7,1],dayNames=[1:tr("Sun","일"),2:tr("Mon","월"),3:tr("Tue","화"),4:tr("Wed","수"),5:tr("Thu","목"),6:tr("Fri","금"),7:tr("Sat","토")]
    var action:ScheduleAction { switch kind { case .limit:return .setLimit(limit);case .topUp:return .topUp;case .off:return .clearLimit } }
    var hm:(Int,Int) { let c=Calendar.current.dateComponents([.hour,.minute],from:time);return (c.hour ?? 0,c.minute ?? 0) }
    var draft:ChargeScheduleRule {
        var r=rule ?? ChargeScheduleRule(name:"",weekdays:[],hour:0,minute:0,action:.topUp,activeSince:Date())
        r.weekdays=days;(r.hour,r.minute)=hm;r.action=action
        r.name=nameEdited && !name.trimmingCharacters(in:.whitespaces).isEmpty ? name:ScheduleText.sentence(r)
        return r
    }
    var collides:Bool { let (h,m)=hm;return others.contains { $0.enabled && $0.hour==h && $0.minute==m && !$0.weekdays.isDisjoint(with:days) } }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(rule==nil ? tr("Add schedule","일정 추가"):tr("Edit schedule","일정 편집")).font(.title2.bold())
            VStack(alignment:.leading,spacing:8) {
                Text(tr("Days","요일")).font(.headline)
                HStack {
                    ForEach([(tr("Every day","매일"),Set(1...7)),(tr("Weekdays","평일"),Set(2...6)),(tr("Weekends","주말"),Set([1,7]))],id:\.0) { label,set in
                        Button(label) { days=set }.buttonStyle(.bordered).tint(days==set ? .mint:.secondary)
                    }
                }
                HStack(spacing:6) {
                    ForEach(dayOrder,id:\.self) { d in
                        Button(dayNames[d]!) { if days.contains(d) { days.remove(d) } else { days.insert(d) } }
                            .buttonStyle(.borderedProminent).tint(days.contains(d) ? .mint:Color.secondary.opacity(0.35))
                    }
                }
            }
            DatePicker(tr("Time","시각"),selection:$time,displayedComponents:.hourAndMinute).font(.headline)
            VStack(alignment:.leading,spacing:8) {
                Text(tr("Action","할 일")).font(.headline)
                Picker(tr("Action","할 일"),selection:$kind) { ForEach(Kind.allCases,id:\.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                if kind == .limit { Stepper(tr("Limit \(limit)%\(limit==80 ? " (recommended)":"")","상한 \(limit)%\(limit==80 ? " (권장)":"")"),value:$limit,in:ChargeCommand.range,step:ChargeCommand.step) }
                if kind == .limit && limit<ChargeCommand.userFloor { Text(tr("Limits below 80% need the charge helper to be installed.","80% 미만은 충전 헬퍼가 설치되어 있어야 합니다.")).font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment:.leading,spacing:6) {
                Text(tr("Name","이름")).font(.headline)
                TextField(ScheduleText.sentence(draft),text:Binding(get:{ nameEdited ? name:"" },set:{ name=$0;nameEdited = !$0.isEmpty }))
            }
            if collides { Label(tr("Another schedule is set for the same time. The one lower in the list applies.","같은 시각에 다른 일정이 있어요. 목록에서 아래쪽 일정이 적용됩니다."),systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if days.isEmpty { Text(tr("Pick at least one day.","요일을 하나 이상 고르세요.")).font(.caption).foregroundStyle(.orange) }
            HStack {
                if let onDelete { Button(tr("Delete","삭제"),role:.destructive) { onDelete();dismiss() } }
                Spacer()
                Button(tr("Cancel","취소")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Save","저장")) { onSave(draft);dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(days.isEmpty || (rule==nil && others.count>=SchedulePolicy.maxRules))
            }
        }
        .padding(24).frame(width:440)
        .onAppear {
            guard let r=rule else { return }
            days=r.weekdays;time=Calendar.current.date(from:DateComponents(hour:r.hour,minute:r.minute)) ?? time
            switch r.action { case .setLimit(let p):kind = .limit;limit=p;case .topUp:kind = .topUp;case .clearLimit:kind = .off }
            if !ScheduleText.isAutoName(r.name,for:r) { name=r.name;nameEdited=true }
        }
    }
}
struct HeatCard:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        Card {
            Text(tr("Hold charging when hot","과열 시 충전 보류")).font(.headline)
            Toggle(tr("Hold charging when the battery is hot","배터리 온도가 높으면 충전 보류"),isOn:Binding(get:{ model.preferences.heat.enabled },set:{ model.setHeatEnabled($0) }))
            Stepper(tr("Hold at \(Int(model.preferences.heat.holdAt))°C","보류 온도 \(Int(model.preferences.heat.holdAt))°C"),value:$model.preferences.heat.holdAt,in:30...45,step:1).onChange(of:model.preferences.heat.holdAt) { _,_ in model.savePreferences() }
            Stepper(tr("Resume at \(Int(model.preferences.heat.resumeAt))°C","재개 온도 \(Int(model.preferences.heat.resumeAt))°C"),value:$model.preferences.heat.resumeAt,in:25...44,step:1).onChange(of:model.preferences.heat.resumeAt) { _,_ in model.savePreferences() }
            Text(tr("The defaults of 35°C/32°C are conservative design values, not an Apple standard. It lowers the limit to the current charge only while charging at 50% or more, and only while the app is running. It does not replace Apple's hardware protection.","기본값 35°C/32°C는 Apple 공식 기준이 아닌 보수적 설계값입니다. 잔량 50% 이상에서 충전 중일 때만 상한을 현재 잔량으로 낮추며, 앱이 실행 중일 때만 동작합니다. Apple의 하드웨어 보호를 대체하지 않습니다.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct HelperLogCard:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        Card {
            DisclosureGroup(tr("Helper and log","헬퍼와 기록")) {
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text(ChargeHelperText.status(model)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled);Spacer();Button(tr("Check again","다시 확인")) { model.checkHelper() }.controlSize(.small) }
                    HelperInstallControls()
                    Divider()
                    Text(tr("Recent charge changes","최근 충전 변경")).font(.subheadline.weight(.semibold))
                    if model.chargeLog.isEmpty { Text(tr("No records yet.","아직 기록이 없습니다.")).font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(model.chargeLog.reversed().enumerated()),id:\.offset) { _,w in
                        Text(ChargeText.logLine(w,now:Date(),calendar:.current)).font(.caption.monospacedDigit()).foregroundStyle(w.ok ? Color.secondary:Color.orange)
                    }
                }.padding(.top,6)
            }
        }
    }
}
