// Logger.swift
import Foundation

enum Logger {
    static func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("🐞 [DEBUG] \(file):\(line) \(function) — \(message)")
    }
    static func info(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("ℹ️ [INFO]  \(file):\(line) \(function) — \(message)")
    }
    static func warn(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("⚠️ [WARN]  \(file):\(line) \(function) — \(message)")
    }
    static func error(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("❌ [ERROR] \(file):\(line) \(function) — \(message)")
    }
}
