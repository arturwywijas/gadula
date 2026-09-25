#!/usr/bin/swift
import Foundation

let katalogRepo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let proces = Process()
proces.executableURL = URL(fileURLWithPath: "/usr/bin/env")
proces.arguments = ["swift", "run", "GadulaIconGenerator"]
proces.currentDirectoryURL = katalogRepo
try proces.run()
proces.waitUntilExit()
exit(proces.terminationStatus)
