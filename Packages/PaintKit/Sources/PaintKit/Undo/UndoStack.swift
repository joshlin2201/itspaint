import Foundation

/// A bounded undo/redo history of `PixelEdit`s.
///
/// Bounded by **bytes**, not by step count. A count limit ("keep 50 steps") is
/// the wrong unit for a paint app: fifty one-pixel dots and fifty full-canvas
/// fills differ by four orders of magnitude in memory. Budgeting bytes keeps
/// the ceiling predictable no matter what the user draws.
public struct UndoStack: Sendable {
    /// Default ceiling for retained history.
    public static let defaultByteBudget = 512 * 1024 * 1024

    public let byteBudget: Int
    private var undoable: [PixelEdit] = []
    private var redoable: [PixelEdit] = []

    public init(byteBudget: Int = UndoStack.defaultByteBudget) {
        self.byteBudget = byteBudget
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
