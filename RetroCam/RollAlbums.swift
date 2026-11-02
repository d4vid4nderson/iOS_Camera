import Photos

/// Files each roll into its own album ("Roll 07 · CLASSIC 400") inside an "Exposures" folder
/// in Photos. Needs full Photos access; with limited or add-only access the shot is saved
/// to the library without an album, as before.
///
/// Saves run one at a time (see `CameraModel`), so two frames finishing together can't
/// both create the roll's album.
enum RollAlbums {
    static let folderTitle = "Exposures"
    /// The folder's name before the app was renamed; renamed in place when found.
    private static let legacyFolderTitles = ["Mono36"]
    private static let albumsKey = "roll.albums"   // roll number -> album local identifier

    enum Outcome {
        case filed           // saved into the roll's album
        case savedUnfiled    // saved, but no permission to make albums
    }

    static func save(_ jpeg: Data, to roll: Roll) async throws -> Outcome {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized else {
            try await Darkroom.saveToLibrary(jpeg)
            return .savedUnfiled
        }

        let album = try await album(for: roll)
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: .photo, data: jpeg, options: nil)
            if let placeholder = creation.placeholderForCreatedAsset,
               let change = PHAssetCollectionChangeRequest(for: album) {
                change.addAssets([placeholder] as NSArray)
            }
        }
        return .filed
    }

    /// Forget a deleted roll's album. With `deletingPhotos`, also delete the album and
    /// every photo in it from Photos — iOS asks the user to confirm, and this throws if
    /// they decline. Returns how many photos were deleted, or nil if the album wasn't found
    /// (no Full Access, or it was already removed in Photos).
    @discardableResult
    static func remove(rollNumber: Int, deletingPhotos: Bool) async throws -> Int? {
        var ids = UserDefaults.standard.dictionary(forKey: albumsKey) as? [String: String] ?? [:]
        let key = String(rollNumber)
        var deleted: Int?
        if deletingPhotos, let id = ids[key],
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            let assets = PHAsset.fetchAssets(in: album, options: nil)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
                PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
            }
            deleted = assets.count
        }
        ids[key] = nil
        UserDefaults.standard.set(ids, forKey: albumsKey)
        return deleted
    }

    /// The roll's album, created (inside the Exposures folder) the first time it's needed.
    private static func album(for roll: Roll) async throws -> PHAssetCollection {
        var ids = UserDefaults.standard.dictionary(forKey: albumsKey) as? [String: String] ?? [:]
        let key = String(roll.number)
        if let id = ids[key],
           let existing = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return existing
        }

        let folder = try await currentFolder()
        var albumID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: roll.albumTitle)
            let placeholder = albumRequest.placeholderForCreatedAssetCollection
            albumID = placeholder.localIdentifier
            if let folder, let folderChange = PHCollectionListChangeRequest(for: folder) {
                folderChange.addChildCollections([placeholder] as NSArray)
            } else {
                let folderRequest = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: folderTitle)
                folderRequest.addChildCollections([placeholder] as NSArray)
            }
        }
        guard let albumID,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject
        else { throw CameraError.processingFailed }
        ids[key] = albumID
        UserDefaults.standard.set(ids, forKey: albumsKey)
        return created
    }

    private static func folder(titled title: String) -> PHCollectionList? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", title)
        return PHCollectionList.fetchCollectionLists(with: .folder, subtype: .regularFolder, options: options).firstObject
    }

    /// The Exposures folder if there is one. A folder from before the rename ("Mono36") is
    /// renamed in place, so its roll albums stay together.
    private static func currentFolder() async throws -> PHCollectionList? {
        if let existing = folder(titled: folderTitle) { return existing }
        for legacy in legacyFolderTitles {
            guard let old = folder(titled: legacy) else { continue }
            try await PHPhotoLibrary.shared().performChanges {
                PHCollectionListChangeRequest(for: old)?.title = folderTitle
            }
            return folder(titled: folderTitle) ?? old
        }
        return nil
    }
}
