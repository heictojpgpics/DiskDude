//
//  SystemMonitor.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + imports:
//  - CPU: host_processor_info / host_cpu_load_info (ticks)
//  - Memory: host_statistics64 (VM stats)
//  - Load average: getloadavg
//  - Processes: proc_listpids + proc_name + proc_pid_rusage
//  - Network: getifaddrs deltas per interface
//

import Foundation
import Darwin

enum SystemMonitor {

    struct Snapshot: Equatable {
        var cpu = CPUStats()
        var memory = MemoryStats()
        var network = NetworkStats()
        var topProcessesByCPU: [ProcessStat] = []
        var topProcessesByMemory: [ProcessStat] = []
        var processCount = 0
    }

    struct CPUStats: Equatable {
        var user: Double = 0
        var system: Double = 0
        var idle: Double = 0
        var loadAverage: Double = 0
    }

    struct MemoryStats: Equatable {
        var wired: Int64 = 0
        var compressed: Int64 = 0
        var active: Int64 = 0
        var inactive: Int64 = 0
        var free: Int64 = 0
        var total: Int64 = 0

        var used: Int64 { total - free }
        var pressure: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    struct NetworkStats: Equatable {
        var downBytesPerSec: Double = 0
        var upBytesPerSec: Double = 0
        var sessionDown: Int64 = 0
        var sessionUp: Int64 = 0
    }

    struct ProcessStat: Identifiable, Hashable {
        var pid: Int32
        var name: String
        var cpuPercent: Double
        var memoryBytes: Int64

        var id: Int32 { pid }
    }

    /// Mutable sampling state kept between polls (class State, recovered
    /// as _TtCO8DiskDude13SystemMonitorP33_...State with previousCPU,
    /// previousProcessTimes, previousNet, sessionStart).
    final class State {
        var previousCPU: host_cpu_load_info?
        var previousProcessTimes: [Int32: (Double, Double)] = [:]
        var previousNet: [String: (Int64, Int64)] = [:]
        var sessionStart: Date = Date()

        init() {
            previousCPU = readCPULoadInfo()
            sessionStart = Date()
        }
    }

    /// Total physical memory (sysctlbyname "hw.memsize" — recovered string).
    static var totalMemory: Int64 {
        var size: Int64 = 0
        var len = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }

    static func readCPULoadInfo() -> host_cpu_load_info? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// Poll every stat block ("Pressure over time", "Free space over time").
    static func sample(state: State) -> Snapshot {
        var snap = Snapshot()
        snap.cpu = cpuStats(state: state)
        snap.memory = memoryStats()
        snap.network = networkStats(state: state)
        let (procs, count) = processStats(state: state)
        snap.topProcessesByCPU = Array(procs.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(8))
        snap.topProcessesByMemory = Array(procs.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(8))
        snap.processCount = count
        return snap
    }

    static func cpuStats(state: State) -> CPUStats {
        var stats = CPUStats()
        var load: [Double] = [0, 0, 0]
        getloadavg(&load, 3)
        stats.loadAverage = load[0]
        guard let current = readCPULoadInfo() else { return stats }
        defer { state.previousCPU = current }
        guard let previous = state.previousCPU else { return stats }

        let user = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let system = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let idle = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle
        guard total > 0 else { return stats }
        stats.user = user / total * 100
        stats.system = system / total * 100
        stats.idle = idle / total * 100
        return stats
    }

    static func memoryStats() -> MemoryStats {
        var stats = MemoryStats()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats }
        let pageSize = Int64(vm_kernel_page_size)
        stats.free = Int64(vm.free_count) * pageSize
        stats.active = Int64(vm.active_count) * pageSize
        stats.inactive = Int64(vm.inactive_count) * pageSize
        stats.wired = Int64(vm.wire_count) * pageSize
        stats.compressed = Int64(vm.compressor_page_count) * pageSize
        stats.total = totalMemory
        return stats
    }

    static func networkStats(state: State) -> NetworkStats {
        var stats = NetworkStats()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return stats }
        defer { freeifaddrs(ifaddr) }

        var current: [String: (Int64, Int64)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data64.self) else { continue }
            if name.hasPrefix("en") || name.hasPrefix("lo") == false {
                current[name, default: (0, 0)].0 = Int64(data.pointee.ifi_ibytes)
                current[name, default: (0, 0)].1 = Int64(data.pointee.ifi_obytes)
            }
        }
        let now = Date()
        let elapsed = max(0.25, now.timeIntervalSince(state.sessionStart))
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        for (name, (inBytes, outBytes)) in current {
            if let (prevIn, prevOut) = state.previousNet[name] {
                let dIn = inBytes - prevIn
                let dOut = outBytes - prevOut
                if dIn > 0 { totalIn += dIn }
                if dOut > 0 { totalOut += dOut }
            }
        }
        state.previousNet = current
        stats.downBytesPerSec = Double(totalIn) / elapsed
        stats.upBytesPerSec = Double(totalOut) / elapsed
        for (_, (inBytes, outBytes)) in current {
            stats.sessionDown += inBytes
            stats.sessionUp += outBytes
        }
        return stats
    }

    static func processStats(state: State) -> ([ProcessStat], Int) {
        var buffer = [Int32](repeating: 0, count: 8192)
        let count = proc_listpids(UInt32(KERN_PROC_ALL), 0, &buffer, Int32(MemoryLayout<Int32>.size * 8192))
        guard count > 0 else { return ([], 0) }
        let pidCount = Int(count) / MemoryLayout<Int32>.size
        var stats: [ProcessStat] = []
        for i in 0..<pidCount {
            let pid = buffer[i]
            guard pid > 0 else { continue }
            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let nameLen = proc_name(pid, &nameBuf, Int32(MAXPATHLEN))
            let name = nameLen > 0 ? String(cString: nameBuf) : "pid \(pid)"
            var rusage = rusage_info_current()
            let rsize = MemoryLayout<rusage_info_current>.size
            let result = withUnsafeMutablePointer(to: &rusage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { ptr in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, ptr)
                }
            }
            var memBytes: Int64 = 0
            var cpuNanos: UInt64 = 0
            if result == 0 {
                memBytes = Int64(rusage.ri_resident_size)
                cpuNanos = rusage.ri_user_time + rusage.ri_system_time
            }
            let cpuSeconds = Double(cpuNanos) / 1_000_000_000
            let cpuPercent: Double
            if let (prevTime, prevWall) = state.previousProcessTimes[pid] {
                let dCPU = cpuSeconds - prevTime
                let dWall = max(0.1, Date().timeIntervalSince1970 - prevWall)
                cpuPercent = min(400.0, dCPU / dWall * 100)
            } else {
                cpuPercent = 0
            }
            state.previousProcessTimes[pid] = (cpuSeconds, Date().timeIntervalSince1970)
            stats.append(ProcessStat(pid: pid, name: name, cpuPercent: cpuPercent, memoryBytes: memBytes))
        }
        return (stats, pidCount)
    }
}
