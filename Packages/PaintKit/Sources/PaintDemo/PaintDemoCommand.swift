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

        if arguments.first == "--scene" {
            guard arguments.count == 3, let scene = DemoScene(rawValue: arguments[1]) else {
                printSceneUsage()
                return 2
            }
            return write(scene.render(), to: url(for: arguments[2], currentDirectory: currentDirectory))
        }

        let output = arguments.first.map { url(for: $0, currentDirectory: currentDirectory) }
            ?? currentDirectory.appendingPathComponent("itspaint-sample.png")
        return write(LegacyClipboardDemo.render(), to: output)
    }

    @MainActor
    private static func write(_ canvas: DemoCanvas, to output: URL) -> Int32 {
        do {
            try ImageCodec.write(canvas.engine.canvas, to: output, as: .png)
            print("Wrote \(canvas.engine.canvas.width)×\(canvas.engine.canvas.height) to \(output.path)")
            print("Undo steps recorded: \(canvas.engine.undoStack.undoCount)")
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
        writeError("Usage: paint-demo --scene <clipboard|quick-sketch|transparency> <output.png>\n")
    }

    private static func printHelp() {
        print("""
        Usage:
          paint-demo [output.png]
          paint-demo --scene <clipboard|quick-sketch|transparency> <output.png>
          paint-demo --bench
          paint-demo --icon [output-directory]
          paint-demo --social <window-capture> <output.png>
        """)
    }
}
