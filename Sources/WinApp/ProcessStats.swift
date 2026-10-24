import Darwin
import Foundation

struct AppUsage: Equatable {
    var cpu: Double      // percent of one core (Activity Monitor style), smoothed over a few samples
    var memory: UInt64   // physical footprint in bytes, app plus its helper processes
}

enum UsageLevel { case normal, high, critical }

enum MemoryPressure: Int32 { case normal = 1, warning = 2, critical = 4 }

enum UsageFormat {
    static func cpu(_ percent: Double) -> String {
        if percent < 0.5 { return percent < 0.05 ? "0%" : "<1%" }
        return "\(Int(percent.rounded()))%"
    }

    static func memory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 999.5 { return "\(Int(mb.rounded())) MB" }
        return String(format: "%.1f GB", mb / 1024)
    }

    static func cpuLevel(_ percent: Double) -> UsageLevel {
        percent >= 90 ? .critical : percent >= 40 ? .high : .normal
    }

    // macOS keeps RAM full on purpose, so a big number alone is not a problem.
    // Only flag the large apps once the system is actually short of memory.
    static func memoryLevel(_ bytes: UInt64, pressure: MemoryPressure) -> UsageLevel {
        guard bytes >= 1 << 30 else { return .normal }
        switch pressure {
        case .normal: return .normal
        case .warning: return .high
        case .critical: return .critical
        }
    }
}

private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
// Private libsystem call Activity Monitor uses to attribute XPC helpers
// (e.g. Safari's WebContent processes) to the app that spawned them.
private let responsiblePID: ResponsibleFunction? = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                         "responsibility_get_pid_responsible_for_pid")
    .map { unsafeBitCast($0, to: ResponsibleFunction.self) }

/// Samples every process in the background so the switcher can show numbers
/// instantly. Each process is credited to its ancestors and its responsible
/// app, so an app's totals include its helper processes.
final class ProcessStats {
    private(set) var usage: [pid_t: AppUsage] = [:]   // main thread only
    private(set) var pressure: MemoryPressure = .normal
    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "pcmode.process-stats", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastTime: UInt64 = 0
    private var smoothed: [pid_t: Double] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(3), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
    }

    private func sample() {
        let now = DispatchTime.now().uptimeNanoseconds
        let pids = allPIDs()
        var parents: [pid_t: pid_t] = [:]
        var cpuTimes: [pid_t: UInt64] = [:]
        var footprints: [pid_t: UInt64] = [:]
        for pid in pids where pid > 0 {
            var bsd = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size { parents[pid] = pid_t(bsd.pbi_ppid) }
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard result == 0 else { continue }
            // rusage CPU times are mach ticks (not ns) on Apple silicon.
            let ticks = info.ri_user_time + info.ri_system_time
            cpuTimes[pid] = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
            footprints[pid] = info.ri_phys_footprint
        }

        let elapsed = lastTime > 0 ? Double(now - lastTime) : 0
        var cpuTotals: [pid_t: Double] = [:]
        var memoryTotals: [pid_t: UInt64] = [:]
        for (pid, footprint) in footprints {
            var delta: Double = 0
            if elapsed > 0, let previous = lastCPU[pid], let current = cpuTimes[pid], current >= previous {
                delta = Double(current - previous)
            }
            var owners: Set<pid_t> = [pid]
            var cursor = pid
            while let parent = parents[cursor], parent > 1, owners.insert(parent).inserted { cursor = parent }
            if let responsible = responsiblePID?(pid), responsible > 1 { owners.insert(responsible) }
            for owner in owners {
                cpuTotals[owner, default: 0] += delta
                memoryTotals[owner, default: 0] += footprint
            }
        }

        var result: [pid_t: AppUsage] = [:]
        var nextSmoothed: [pid_t: Double] = [:]
        for (pid, memory) in memoryTotals {
            let instant = elapsed > 0 ? (cpuTotals[pid] ?? 0) / elapsed * 100 : 0
            let cpu = smoothed[pid].map { $0 * 0.5 + instant * 0.5 } ?? instant
            nextSmoothed[pid] = cpu
            result[pid] = AppUsage(cpu: cpu, memory: memory)
        }
        smoothed = nextSmoothed
        lastCPU = cpuTimes
        lastTime = now

        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure = MemoryPressure(rawValue: level) ?? .normal

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.usage = result
            self.pressure = pressure
            self.onUpdate?()
        }
    }

    private func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(filled, 0))))
    }
}
