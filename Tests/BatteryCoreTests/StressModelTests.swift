import Testing
@testable import BatteryCore
struct StressModelTests {
    @Test func reproducesBU808Table() {
        #expect(abs(StressModel.rate(soc:40,temperature:25)-1)<1e-9)
        #expect(abs(StressModel.rate(soc:100,temperature:25)-5)<1e-9)
        #expect(abs(StressModel.rate(soc:100,temperature:40)-8.75)<1e-9)
        #expect(abs(StressModel.rate(soc:40,temperature:0)-0.5)<1e-9)
        #expect(abs(StressModel.rate(soc:80,temperature:25)-11.0/3.0)<1e-9)
    }
    @Test func increasesWithChargeAndTemperature() {
        var previous=0.0
        for soc in stride(from:40.0,through:100,by:5) { let r=StressModel.rate(soc:soc,temperature:30);#expect(r>previous);previous=r }
        previous=0
        for t in stride(from:0.0,through:60,by:5) { let r=StressModel.rate(soc:80,temperature:t);#expect(r>previous);previous=r }
    }
    @Test func clampsOutsideTheTable() {
        #expect(StressModel.rate(soc:10,temperature:25)==StressModel.rate(soc:40,temperature:25))
        #expect(StressModel.rate(soc:80,temperature:-10)==StressModel.rate(soc:80,temperature:0))
        #expect(StressModel.rate(soc:80,temperature:90)==StressModel.rate(soc:80,temperature:60))
    }
}
