import Foundation

/// The document, as PNG bytes and a file name for a drag into another app.
///
/// **Why this exists at all:** every other way out of the app writes a file
/// first. Export opens a panel and asks where; Copy needs somewhere to paste it.
/// Dragging the image straight into a Slack message, a Mail draft or a Finder
/// window is the shortest path there is, and it is the single most-named thing
/// people say they lost when Skitch stopped working — *"I love how Skitch lets
/// me do that, saving the step of having to save it to disk."*
///
/// The header's drag handle hands these to an `NSFilePromiseProvider`, which is
/// what carries the name across, so the drop lands as "Receipt.png" rather than
/// "image.png".
struct DraggedImage {
    let data: Data
    let name: String
}
