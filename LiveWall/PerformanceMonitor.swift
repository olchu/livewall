import Foundation
import Metal

struct PerformanceSnapshot {
    let cpu: Double    // percent, e.g. 3.2
    let ram: UInt64    // bytes
    let gpu: UInt64    // bytes (device-wide Metal allocation — sandbox limitation)

    var ramFormatted: String { ByteCountFormatter.string(fromByteCount: Int64(ram), countStyle: .memory) }
    var gpuFormatted: String { ByteCountFormatter.string(fromByteCount: Int64(gpu), countStyle: .memory) }
    var cpuFormatted: String { String(format: "%.1f%%", cpu) }
}

final class PerformanceMonitor {
    private let metalDevice = MTLCreateSystemDefaultDevice()

    func snapshot() -> PerformanceSnapshot {
        PerformanceSnapshot(cpu: cpuUsage(), ram: ramUsage(), gpu: gpuUsage())
    }

    // MARK: - CPU (per-process, all threads)
    private func cpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }

        var total: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE)
            }
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: threadList),
            vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride)
        )
        return total * 100
    }

    // MARK: - RAM (physical footprint of this process)
    private func ramUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    // MARK: - GPU (device-wide Metal allocation; per-process not available in sandbox)
    private func gpuUsage() -> UInt64 {
        guard let device = metalDevice else { return 0 }
        return UInt64(device.currentAllocatedSize)
    }
}
