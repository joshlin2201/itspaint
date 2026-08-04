import Foundation

/// A bounded undo/redo history of `PixelEdit`s.
///
/// Bounded by **bytes**, not by step count. A count limit ("keep 50 steps") is
/// the wrong unit for a paint app: fifty one-pixel dots and fifty full-canvas
/// fills differ by four orders of magnitude in memory. Budgeting bytes keeps
/// the ceiling predictable no matter what the user draws.
public struct UndoStack: Sendable {
    /// Ceiling for retained history when nothing is known about the canvas.
    ///
    /// Deliberately modest. This used to be 512 MB — half the RAM of an 8 GB
    /// Mac, held by a *single document*, and unrelated to what was being
    /// edited. `record(_:canvasBytes:)` replaces it with a canvas-relative
    /// budget as soon as the first edit lands.
    public static let defaultByteBudget = 64 * 1024 * 1024

    /// Hard ceiling, whatever the canvas size. A maximum-size canvas is 128 MiB,
    /// and a resize edit carries two of them, so this is the smallest number
    /// that still leaves one crop of a 33-megapixel screenshot undoable.
    public static let maximumByteBudget = 256 * 1024 * 1024

    /// Floor, so a small canvas still gets a usable history rather than three
    /// strokes' worth.
    public static let minimumByteBudget = 32 * 1024 * 1024

    /// History worth about a dozen full-canvas edits, bounded at both ends.
    ///
    /// Budgeting against the canvas is what keeps the ceiling honest: the same
    /// number that gives a 1200×800 sketch a deep history gives a 33-megapixel
    /// screenshot a gigabyte of retained pixels.
    public static func budget(forCanvasBytes bytes: Int) -> Int {
        min(maximumByteBudget, max(minimumByteBudget, bytes * 12))
    }

    public private(set) var byteBudget: Int

    /// A budget the owner asked for by name, which no canvas may override.
    /// `nil` means "follow the canvas".
    private let fixedBudget: Int?

    private var undoable: [PixelEdit] = []
    private var redoable: [PixelEdit] = []

    public init(byteBudget: Int? = nil) {
        self.fixedBudget = byteBudget
        self.byteBudget = byteBudget ?? Self.defaultByteBudget
    }

    public var canUndo: Bool { !undoable.isEmpty }
    public var canRedo: Bool { !redoable.isEmpty }
    public var undoCount: Int { undoable.count }

    /// Name of the next undo/redo action, for the Edit menu ("Undo Pencil").
    public var undoActionName: String? { undoable.last?.name }
    public var redoActionName: String? { redoable.last?.name }

    /// Bytes currently retained.
    ///
    /// Kept as a running total rather than re-summed on demand: it is consulted
    /// once per recorded edit, and re-adding every patch each time made building
    /// a long history quadratic in the number of strokes.
    public private(set) var byteCount = 0

    /// Record an edit, sizing the budget to the canvas it was made on.
    ///
    /// The canvas is passed in rather than remembered because it changes under
    /// the stack: crop, trim and paste-to-fit all resize it, and a history
    /// budget pinned to the size the document opened at is the one that goes
    /// wrong on exactly the documents where memory matters.
    public mutating func record(_ edit: PixelEdit, canvasBytes: Int) {
        byteBudget = fixedBudget ?? Self.budget(forCanvasBytes: canvasBytes)
        record(edit)
    }

    public mutating func record(_ edit: PixelEdit) {
        // Any new edit invalidates the redo branch — standard linear history.
        byteCount -= redoable.reduce(0) { $0 + $1.byteCount }
        redoable.removeAll(keepingCapacity: true)
        undoable.append(edit)
        byteCount += edit.byteCount
        trimToBudget()
    }

    @discardableResult
    public mutating func undo(on bitmap: inout Bitmap) -> PixelEdit? {
        guard let edit = undoable.popLast() else { return nil }
        edit.undo(on: &bitmap)
        redoable.append(edit)
        return edit
    }

    @discardableResult
    public mutating func redo(on bitmap: inout Bitmap) -> PixelEdit? {
        guard let edit = redoable.popLast() else { return nil }
        edit.redo(on: &bitmap)
        undoable.append(edit)
        return edit
    }

    public mutating func removeAll() {
        undoable.removeAll()
        redoable.removeAll()
        byteCount = 0
    }

    /// Drop the oldest history until the budget is met. Always keeps at least
    /// one step, so a single enormous edit is still undoable.
    private mutating func trimToBudget() {
        while byteCount > byteBudget, undoable.count > 1 {
            byteCount -= undoable.removeFirst().byteCount
        }
    }
}
