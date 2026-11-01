import os

/// Console.app에서 `com.kyun.clipboard-manager`로 필터링해서 볼 수 있음
enum Log {
    static let app = Logger(subsystem: "com.kyun.clipboard-manager", category: "app")
    static let storage = Logger(subsystem: "com.kyun.clipboard-manager", category: "storage")
}
