import UIKit

/// Sharing a film's recipe: the film's card (a frame you shot on it, or its tone scale)
/// and its link, handed straight to the share sheet. Scanning the card's code or tapping
/// the link opens Exposures and offers to add the film, every setting included.
enum FilmShare {
    /// The card and link for the share sheet, or nil if the film can't be packed into a
    /// link. Reads frames from disk: call it off the main thread.
    static func items(for film: FilmStock) -> [Any]? {
        guard let url = FilmCode.url(for: film) else { return nil }
        let profile = Profile.load()
        let photo = profile.filmCardsUsePhoto ? RollStore.latestFrame(filmID: film.id) : nil
        let sharer = profile.showOnCards && !profile.isEmpty
            ? FilmCodeCard.Sharer(name: profile.name, avatar: profile.photo) : nil
        let card = FilmCodeCard.render(film: film, url: url, photo: photo, sharer: sharer)
        return [card as Any?, url].compactMap { $0 }
    }
}
