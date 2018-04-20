import Foundation
import Photos

extension PostSettingsViewController {

    @objc func setFeaturedImage(asset: PHAsset) {
        let media = MediaCoordinator.shared.addMedia(from: asset, to: self.apost)
        apost.featuredImage = media
        setupObservingOf(media: media)
    }

    @objc func setFeaturedImage(media: Media) {
       apost.featuredImage = media
        if !media.hasRemote {
            MediaCoordinator.shared.retryMedia(media)
            setupObservingOf(media: media)
        }
    }

    @objc func removeMediaObserver() {
        if let receipt = mediaObserverReceipt {
            MediaCoordinator.shared.removeObserver(withUUID: receipt)
            mediaObserverReceipt = nil
        }
    }

    @objc func setupObservingOf(media: Media) {
        removeMediaObserver()
        isUploadingMedia = true
        mediaObserverReceipt = MediaCoordinator.shared.addObserver({ [weak self](media, state) in
            self?.mediaObserver(media: media, state: state)
        })
        let progress = MediaCoordinator.shared.progress(for: media)
        if let url = media.absoluteThumbnailLocalURL, let data = try? Data(contentsOf: url) {
          progress?.setUserInfoObject(UIImage(data: data), forKey: .WPProgressImageThumbnailKey)
        }
        featuredImageProgress = progress
    }

    func mediaObserver(media: Media, state: MediaCoordinator.MediaState) {
        switch state {
        case .processing:
            featuredImageProgress?.localizedDescription = NSLocalizedString("Preparing...", comment: "Label to show while converting and/or resizing media to send to server")
        case .thumbnailReady:
            if let url = media.absoluteThumbnailLocalURL, let data = try? Data(contentsOf: url) {
                featuredImageProgress?.setUserInfoObject(UIImage(data: data), forKey: .WPProgressImageThumbnailKey)
            }
        case .uploading(let progress):
            featuredImageProgress = progress
            featuredImageProgress?.kind = .file
            featuredImageProgress?.setUserInfoObject(Progress.FileOperationKind.copying, forKey: ProgressUserInfoKey.fileOperationKindKey)
            featuredImageProgress?.localizedDescription = NSLocalizedString("Uploading...", comment: "Label to show while uploading media to server")
            progressCell?.setProgress(progress)
            tableView.reloadData()
        case .ended:
            isUploadingMedia = false
            tableView.reloadData()
        case .failed(let error):
            DDLogError("Couldn't upload the featured image: \(error.localizedDescription)")
            isUploadingMedia = false
            tableView.reloadData()
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                apost.featuredImage = nil
                apost.removeMediaObject(media)
                break
            }
            WPError.showAlert(withTitle: NSLocalizedString("Couldn't upload the featured image", comment: "The title for an alert that says to the user that the featured image he selected couldn't be uploaded."), message: error.localizedDescription)
        case .progress:
            break
        }
    }

    @objc func showFeaturedImageRemoveOrRetryAction() {
        guard let media = apost.featuredImage else {
            return
        }

        let alertController = UIAlertController(title: FeaturedImageActionSheet.title, message: nil, preferredStyle: .actionSheet)
        alertController.addActionWithTitle(FeaturedImageActionSheet.dismissActionTitle,
                                           style: .cancel,
                                           handler: nil)

        alertController.addActionWithTitle(FeaturedImageActionSheet.retryUploadActionTitle,
                                           style: .default,
                                           handler: { (action) in
                                                self.setFeaturedImage(media: media)
        })

        alertController.addActionWithTitle(FeaturedImageActionSheet.removeActionTitle,
                                           style: .destructive,
                                           handler: { (action) in
                                                self.apost.featuredImage = nil
                                                self.apost.removeMediaObject(media)
        })
        if let error = media.error {
            alertController.message = error.localizedDescription
        }
        let anchorView = self.tableView!
        alertController.popoverPresentationController?.sourceView = anchorView
        alertController.popoverPresentationController?.sourceRect = CGRect(origin: anchorView.center, size: CGSize(width: 1, height: 1))
        alertController.popoverPresentationController?.permittedArrowDirections = .any
        present(alertController, animated: true, completion: nil)
    }

    struct FeaturedImageActionSheet {
        static let title = NSLocalizedString("Featured Image Options", comment: "Title for action sheet with featured media options.")
        static let dismissActionTitle = NSLocalizedString("Dismiss", comment: "User action to dismiss featured media options.")
        static let retryUploadActionTitle = NSLocalizedString("Retry", comment: "User action to retry featured media upload.")
        static let removeActionTitle = NSLocalizedString("Remove", comment: "User action to remove featured media.")
    }

}
