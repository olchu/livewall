import Foundation

enum WallpaperExtensionRegistrar {
    private static let extensionBundleID = "com.ochurkin.LiveWall.WallpaperExtension"
    private static let extensionRelativePath = "Contents/Extensions/LiveWallWallpaperExtension.appex"

    static func bootstrap() {
        let extensionURL = Bundle.main.bundleURL.appendingPathComponent(extensionRelativePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: extensionURL.path) else {
            NSLog("LiveWall: wallpaper extension is missing at %@", extensionURL.path)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let listed = runPlugInKit(arguments: ["-m", "-p", "com.apple.wallpaper"])
            let entry = listed.output.split(separator: "\n").first { $0.localizedCaseInsensitiveContains(extensionBundleID) }
            let isRegistered = entry != nil
            // pluginkit marks extensions already elected for use with a leading "+".
            let isEnabled = entry?.trimmingCharacters(in: .whitespaces).hasPrefix("+") ?? false
            if isEnabled { return }

            if !isRegistered {
                let result = runPlugInKit(arguments: ["-a", extensionURL.path])
                guard result.terminationStatus == 0 else {
                    NSLog("LiveWall: pluginkit registration failed (%d): %@", result.terminationStatus, result.output)
                    return
                }
            }

            let enableResult = runPlugInKit(arguments: ["-e", "use", "-i", extensionBundleID])
            guard enableResult.terminationStatus == 0 else {
                NSLog("LiveWall: pluginkit enable failed (%d): %@", enableResult.terminationStatus, enableResult.output)
                return
            }

            if !isRegistered {
                _ = runCommand(url: URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["WallpaperAgent"])
            }
        }
    }

    private static func runPlugInKit(arguments: [String]) -> CommandResult {
        runCommand(url: URL(fileURLWithPath: "/usr/bin/pluginkit"), arguments: arguments)
    }

    private static func runCommand(url: URL, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return CommandResult(terminationStatus: -1, output: String(describing: error))
        }

        // Drain before waiting — a full pipe would otherwise block the child forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(terminationStatus: process.terminationStatus, output: output)
    }

    private struct CommandResult {
        let terminationStatus: Int32
        let output: String
    }
}
