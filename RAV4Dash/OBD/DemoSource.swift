import Foundation

/// Fake plug-in hybrid data so the dashboard can be tried without the car.
@MainActor
final class DemoSource {
    var onValue: ((MetricID, Double) -> Void)?

    private var task: Task<Void, Never>?
    private var time: Double = 0
    private var battery = 91.0
    private var fuel = 62.0
    private var coolant = 150.0
    private var rpm = 0.0
    private var engineOn = false
    private var nextSwitch = 20.0
    private var runSeconds = 0.0

    var isRunning: Bool { task != nil }

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick(dt: 0.25)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick(dt: Double) {
        time += dt
        if time >= nextSwitch {
            engineOn.toggle()
            nextSwitch = time + (engineOn ? Double.random(in: 8...16) : Double.random(in: 20...40))
        }

        let throttle = max(0, min(100, 22 + 18 * sin(time / 3) + Double.random(in: -3...3)))
        if engineOn {
            rpm += ((1200 + throttle * 28) - rpm) * 0.3
            coolant = min(196, coolant + 1.2 * dt)
            fuel = max(0, fuel - 0.002 * dt)
            runSeconds += dt
        } else {
            rpm *= 0.4
            if rpm < 50 { rpm = 0 }
            coolant = max(150, coolant - 0.15 * dt)
            battery = max(12, battery - 0.03 * dt * (throttle / 25))
        }

        let fuelRate = engineOn ? 0.25 + throttle / 100 * 1.6 : 0
        emit(.rpm, rpm.rounded())
        emit(.throttle, throttle)
        emit(.load, engineOn ? throttle * 0.9 + 10 : 0)
        emit(.hybridBattery, battery)
        emit(.fuelLevel, fuel)
        emit(.fuelRate, fuelRate)
        emit(.coolant, coolant)
        emit(.intakeAir, 72 + sin(time / 20) * 4)
        emit(.ambient, 58)
        emit(.voltage, 14.1 + Double.random(in: -0.05...0.05))
        emit(.maf, engineOn ? 3 + throttle * 0.6 : 0)
        emit(.manifoldPressure, engineOn ? 4 + throttle * 0.1 : 14.6)
        emit(.runTime, runSeconds / 60)
    }

    private func emit(_ metric: MetricID, _ value: Double) {
        onValue?(metric, value)
    }
}
