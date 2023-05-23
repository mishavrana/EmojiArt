//
//  EmojiArtDocument.swift
//  EmojiArt
//
//  Created by CS193p Instructor on 4/26/21.
//  Copyright © 2021 Stanford University. All rights reserved.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

extension UTType {
     static let emojiart = UTType(exportedAs: "misha.vrana.emojiart")
}

class EmojiArtDocument: ObservableObject, ReferenceFileDocument
{
    static var readableContentTypes = [UTType.emojiart ]
    static var writeableContentTypes = [UTType.emojiart ]
    
    required init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            emojiArt = try EmojiArtModel(json: data)
            fetchBackgroundImageDataIfNecessary()
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    
    func snapshot(contentType: UTType) throws -> Data {
        try  emojiArt.json()
    }
    
    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
    
    typealias Snapshot = Data
    
    @Published private(set) var emojiArt: EmojiArtModel {
        didSet {
            
            if emojiArt.background != oldValue.background {
                fetchBackgroundImageDataIfNecessary()
            }
        }
    }
    
    
    
    init() {
        emojiArt = EmojiArtModel()
    }
    
    var emojis: [EmojiArtModel.Emoji] { emojiArt.emojis }
    var background: EmojiArtModel.Background { emojiArt.background }
    
    // MARK: - Background
    
    @Published var backgroundImage: UIImage?
    @Published var backgroundImageFetchStatus = BackgroundImageFetchStatus.idle
    
    enum BackgroundImageFetchStatus: Equatable {
        case idle
        case fetching
        case failed(URL) // L12 added
    }
    
    private var backgroundImageFetchCancellable: AnyCancellable? // Whie this is alive (while the document whith uses the model is open) publisher keeps publishing
    
    private func fetchBackgroundImageDataIfNecessary() {
        backgroundImage = nil
        switch emojiArt.background {
            
        case .url(let url):
             //fetch the url
            backgroundImageFetchStatus = .fetching
            backgroundImageFetchCancellable?.cancel() // Cancelling the last fetch and start a new one
            let session = URLSession.shared
            let publisher = session.dataTaskPublisher(for: url)
                .map { (data, URLResponse) in UIImage(data: data) }
                .replaceError(with: nil )
                .receive(on: DispatchQueue.main)


            backgroundImageFetchCancellable = publisher
                .sink { [weak self] image in
                    self?.backgroundImage = image
                    self?.backgroundImageFetchStatus = (image != nil) ? .idle : .failed(url)
                }
        case .imageData(let data):
            backgroundImage = UIImage(data: data)
        case .blank:
            break
        }
    }
    
    // MARK: - Intent(s)
    
    func setBackground(_ background: EmojiArtModel.Background, undoManager: UndoManager?) {
        undoablyPerfom(operation: "Set Background",with: undoManager) {
            emojiArt.background = background
        }
    }
    
    func addEmoji(_ emoji: String, at location: (x: Int, y: Int), size: CGFloat, undoManager: UndoManager?) {
        undoablyPerfom(operation: "Add \(emoji)",with: undoManager) {
            emojiArt.addEmoji(emoji, at: location, size: Int(size))
        }
    }
    
    func moveEmoji(_ emoji: EmojiArtModel.Emoji, by offset: CGSize, undoManager: UndoManager?) {
        undoablyPerfom(operation: "Move ",with: undoManager) {
            if let index = emojiArt.emojis.index(matching: emoji) {
                emojiArt.emojis[index].x += Int(offset.width)
                emojiArt.emojis[index].y += Int(offset.height)
            }
        }
    }
    
    func scaleEmoji(_ emoji: EmojiArtModel.Emoji, by scale: CGFloat, undoManager: UndoManager?) {
        undoablyPerfom(operation: "Scale",with: undoManager) {
            if let index = emojiArt.emojis.index(matching: emoji) {
                emojiArt.emojis[index].size = Int((CGFloat(emojiArt.emojis[index].size) * scale).rounded(.toNearestOrAwayFromZero))
            }
        }
    }
    
    func deleteEmoji(_ emoji: EmojiArtModel.Emoji) {
        emojiArt.deleteEmoji(emoji: emoji)
    }

    
    // MARK: - Undo
    
    private func undoablyPerfom(operation: String, with undoManager: UndoManager? = nil, doit: () -> Void) {
        let oldEmojiArt = emojiArt
        doit()
        undoManager?.registerUndo(withTarget: self) { myself in
            myself.undoablyPerfom(operation: operation, with: undoManager) {
                myself.emojiArt = oldEmojiArt
            }
            myself.emojiArt = oldEmojiArt
        }
        undoManager?.setActionName(operation)
    }
}
