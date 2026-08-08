import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The document, as a PNG file a drag can carry into another app.
///
/// **Why this exists at all:** every other way out of the app writes a file
/// first. Export opens a panel and asks where; Copy needs somewhere to paste it.
/// Dragging the image straight into a Slack message, a Mail draft or a Finder
/// window is the shortest path there is, and it is the single most-named thing
/// people say they lost when Skitch stopped working — *"I love how Skitch lets
/// me do that, saving the step of having to save it to disk."*
///
/// `DataRepresentation` rather than `FileRepresentation`: a file representation
/// wants a URL that already exists, which means writing a temporary file on
/// every drag whether or not it is ever dropped. This hands over the bytes and
/// lets the receiving app decide, and `suggestedFileName` is what makes Finder
/// and Mail name the result something other than "image.png".
struct DraggedImage: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.name }
    }
}
