import Foundation

public struct RenderJob: Codable, Sendable {
    public let input: String
    public let width: Int
    public let height: Int
    public let points: [Vertex]
    public let background: String
    public let canvas: [Int]
    public let offset: [Int]
    public let social: [Int]

    public init(photo: PhotoRecord, settings: ExportSettings, normalized: URL) throws {
        try photo.validate()
        try settings.validate()
        guard photo.closed else { throw ArtPrepError("Close the outline before exporting.") }
        let layout = try CanvasLayout.make(points: photo.points, margin: settings.margin)
        input = normalized.path
        width = photo.size.width
        height = photo.size.height
        points = photo.points
        background = settings.background
        canvas = [layout.width, layout.height]
        offset = [layout.offsetX, layout.offsetY]
        social = [layout.socialSize.width, layout.socialSize.height]
    }
}

public struct Renderer: Sendable {
    public let executable: URL
    public let scripts: URL

    public init(executable: URL, scripts: URL) {
        self.executable = executable
        self.scripts = scripts
    }

    public static func installedGimp() -> URL? {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        return roots.map { $0.appendingPathComponent("GIMP.app/Contents/MacOS/gimp-console") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func export(photo: PhotoRecord, settings: ExportSettings, to folder: URL) throws -> URL {
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: executable.path) else {
            throw ArtPrepError("GIMP 3 is required. Install GIMP in Applications and try again.")
        }
        let scratch = manager.temporaryDirectory.appendingPathComponent("ArtPrep-\(UUID())")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: scratch) }
        let normalized = scratch.appendingPathComponent("source.png")
        let job = try RenderJob(photo: photo, settings: settings, normalized: normalized)
        try PhotoImage.normalize(
            URL(fileURLWithPath: photo.source), to: normalized, expected: photo.size)
        try JSONEncoder().encode(job).write(to: scratch.appendingPathComponent("job.json"))
        try runGimp(in: scratch)
        return try publish(from: scratch, photo: photo, settings: settings, to: folder)
    }

    private func runGimp(in scratch: URL) throws {
        let profile = scratch.appendingPathComponent("profile")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try "(check-updates no)\n".write(
            to: profile.appendingPathComponent("gimprc"),
            atomically: true, encoding: .utf8)
        let log = scratch.appendingPathComponent("gimp.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--no-shm", "-n", "-i", "-f",
            "--batch-interpreter=python-fu-eval", "-b",
            "import os,sys,runpy; sys.path.insert(0,os.environ['ARTPREP_SCRIPTS']); "
                + "runpy.run_path(os.path.join(os.environ['ARTPREP_SCRIPTS'],'render.py'))",
            "--quit",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["GIMP3_DIRECTORY"] = profile.path
        environment["ARTPREP_JOB"] = scratch.appendingPathComponent("job.json").path
        environment["ARTPREP_SCRIPTS"] = scripts.path
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        try verifyResult(in: scratch, exitCode: process.terminationStatus)
    }

    private func verifyResult(in scratch: URL, exitCode: Int32) throws {
        struct Result: Decodable {
            let success: Bool
            let error: String?
        }
        let resultURL = scratch.appendingPathComponent("result.json")
        let result = try? JSONDecoder().decode(Result.self, from: Data(contentsOf: resultURL))
        guard exitCode == 0, result?.success == true else {
            let text =
                (try? String(
                    contentsOf: scratch.appendingPathComponent("gimp.log"),
                    encoding: .utf8)) ?? "No diagnostic log was available."
            throw ArtPrepError(
                (result?.error ?? "GIMP could not finish the export. Use GIMP 3.")
                    + "\n\n" + String(text.suffix(3000)))
        }
        for name in ["artwork.xcf", "full.jpg", "social.jpg"] {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: scratch.appendingPathComponent(name).path)
            guard (attributes[.size] as? Int ?? 0) > 0 else {
                throw ArtPrepError("GIMP produced an empty \(name). Try exporting again.")
            }
        }
    }

    private func publish(
        from scratch: URL, photo: PhotoRecord, settings: ExportSettings,
        to folder: URL
    ) throws -> URL {
        let manager = FileManager.default
        let staging = folder.appendingPathComponent(".ArtPrep-\(UUID())")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        for name in ["artwork.xcf", "full.jpg", "social.jpg"] {
            try manager.copyItem(
                at: scratch.appendingPathComponent(name),
                to: staging.appendingPathComponent(name))
        }
        let project = SavedProject(photos: [photo], settings: settings)
        try JSONEncoder().encode(project).write(
            to: staging.appendingPathComponent("outline.artprep"))
        var number = 1
        var destination = folder.appendingPathComponent("\(photo.name)-art-prep")
        while manager.fileExists(atPath: destination.path) {
            number += 1
            destination = folder.appendingPathComponent("\(photo.name)-art-prep-\(number)")
        }
        try manager.moveItem(at: staging, to: destination)
        return destination
    }
}
