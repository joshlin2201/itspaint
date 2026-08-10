import Foundation
import PaintKit

@main
struct PaintDemoCommand {
    static func main() {
        exit(MainActor.assumeIsolated {
            run(
                arguments: Array(CommandLine.arguments.dropFirst()),
                currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
        })
    }

    @MainActor
    static func run(arguments: [String], currentDirectory: URL) -> Int32 {
        if arguments.contains("--help") {
            printHelp()
            return 0
        }

        if arguments.contains("--bench") {
            Benchmark.run()
            return 0
        }

        if let index = arguments.firstIndex(of: "--icon") {
            let target = arguments.count > index + 1
                ? url(for: arguments[index + 1], currentDirectory: currentDirectory)
                : currentDirectory
            do {
                try IconGenerator.run(into: target)
                return 0
            } catch {
                writeError("Icon failed: \(error)\n")
                return 1
            }
        }

        if let index = arguments.firstIndex(of: "--social") {
            guard arguments.count > index + 2 else {
                writeError("Usage: paint-demo --social <window-capture> <output.png>\n")
                return 2
            }
            do {
                try SocialPreview.run(
                    windowCapture: url(for: arguments[index + 1], currentDirectory: currentDirectory),
                    output: url(for: arguments[index + 2], currentDirectory: currentDirectory)
                )
                return 0
            } catch {
                writeError("Social preview failed: \(error)\n")
                return 1
            }
        }

        if let index = arguments.firstIndex(of: "--banner") {
            guard arguments.count > index + 2 else {
                writeError("Usage: paint-demo --banner <window-capture> <output.png>\n")
                return 2
            }
            do {
                try ReadmeBanner.run(
                    windowCapture: url(for: arguments[index + 1], currentDirectory: currentDirectory),
                    output: url(for: arguments[index + 2], currentDirectory: currentDirectory)
                )
                return 0
            } catch {
                writeError("Banner failed: \(error)\n")
                return 1
            }
        }

        if let index = arguments.firstIndex(of: "--appstore") {
            guard arguments.count > index + 2 else {
                writeError("Usage: paint-demo --appstore <reel-final-frame.png> <output-dir>\n")
                return 2
            }
            do {
                try AppStoreScreenshots.run(
                    reelFrame: url(for: arguments[index + 1], currentDirectory: currentDirectory),
                    outputDir: url(for: arguments[index + 2], currentDirectory: currentDirectory)
                )
                return 0
            } catch {
                writeError("App Store screenshots failed: \(error)\n")
                return 1
            }
        }

        if arguments.first == "--scene" {
            guard arguments.count == 3, let scene = DemoScene(rawValue: arguments[1]) else {
                printSceneUsage()
                return 2
            }
            let output = url(for: arguments[2], currentDirectory: currentDirectory)
            do {
                try scene.write(to: output)
                print("Wrote scene \(scene.rawValue) to \(output.path)")
                return 0
            } catch {
                writeError("Failed: \(error)\n")
                return 1
            }
        }

        let output = arguments.first.map { url(for: $0, currentDirectory: currentDirectory) }
            ?? currentDirectory.appendingPathComponent("itspaint-sample.png")
        do {
            let bitmap = ChameleonScene.render()
            try ImageCodec.write(bitmap, to: output, as: .png)
            print("Wrote \(bitmap.width)×\(bitmap.height) to \(output.path)")
            return 0
        } catch {
            writeError("Failed: \(error)\n")
            return 1
        }
    }

    private static func url(for path: String, currentDirectory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: currentDirectory)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func printSceneUsage() {
        writeError("Usage: paint-demo --scene <clipboard|quick-sketch|transparency|chameleon> <output.png>\n")
    }

    private static func printHelp() {
        print("""
        Usage:
          paint-demo [output.png]
          paint-demo --scene <clipboard|quick-sketch|transparency|chameleon> <output.png>
          paint-demo --bench
          paint-demo --icon [output-directory]
          paint-demo --social <window-capture> <output.png>
          paint-demo --banner <window-capture> <output.png>
          paint-demo --appstore <reel-final-frame.png> <output-dir>
        """)
    }
}
