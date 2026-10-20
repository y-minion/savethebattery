import Foundation
public struct RunOptions {
    public var hours=4.0; public var screenOff=false; public var cleanup=false; public var allowBattery=false; public var command:[String]=[]
    public static func parse(_ arguments:[String]) throws -> RunOptions {
        var result=RunOptions();var i=0
        while i<arguments.count {
            let a=arguments[i]
            if a=="--" { result.command=Array(arguments.dropFirst(i+1));break }
            switch a {
            case "--hours":
                i+=1
                guard i<arguments.count,let n=Double(arguments[i]),n.isFinite,n>0,n<=168 else { throw OptionError.invalid("--hours: 0보다 크고 168 이하인 시간을 지정하세요.") }
                result.hours=n
            case "--screen-off":result.screenOff=true
            case "--cleanup":result.cleanup=true
            case "--allow-battery":result.allowBattery=true
            default:throw OptionError.invalid("알 수 없는 옵션: \(a)")
            }; i+=1
        }
        guard let first=result.command.first,!first.isEmpty else { throw OptionError.invalid("-- 뒤에 실행할 명령을 지정하세요.") }
        return result
    }
}
public enum OptionError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription:String? { if case .invalid(let s)=self{return s};return nil }
}
