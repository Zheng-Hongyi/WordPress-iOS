import UIKit
import CoreSpotlight
import MobileCoreServices

/// Encapsulates CoreSpotlight operations for WPiOS
///
@objc class SearchManager: NSObject {

    // MARK: - Singleton

    @objc static let shared: SearchManager = SearchManager()
    private override init() {}

    // MARK: - Indexing

    /// Index an item to the on-device index
    ///
    /// - Parameters:
    ///   - item: the item to be indexed
    ///
    @objc func indexItem(_ item: SearchableItemConvertable) {
        indexItems([item])
    }

    /// Index items to the on-device index
    ///
    /// - Parameters:
    ///   - items: the items to be indexed
    ///
    @objc func indexItems(_ items: [SearchableItemConvertable]) {
        let items = items.map({ $0.indexableItem() }).flatMap({ $0 })
        guard !items.isEmpty else {
            return
        }

        CSSearchableIndex.default().indexSearchableItems(items, completionHandler: { (error: Error?) -> Void in
            guard let error = error else {
                return
            }
            DDLogError("Could not index post. Error: \(error.localizedDescription)")
        })

    }

    // MARK: - Removal

    /// Remove an item from the on-device index
    ///
    /// - Parameters:
    ///   - item: item to remove
    ///
    @objc func deleteSearchableItem(_ item: SearchableItemConvertable) {
        deleteSearchableItems([item])
    }

    /// Remove items from the on-device index
    ///
    /// - Parameters:
    ///   - items: items to remove
    ///
    @objc func deleteSearchableItems(_ items: [SearchableItemConvertable]) {
        let ids = items.map({ $0.uniqueIdentifier }).flatMap({ $0 })
        guard !ids.isEmpty else {
            return
        }

        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids, completionHandler: { (error: Error?) -> Void in
            guard let error = error else {
                return
            }
            DDLogError("Could not delete CSSearchableItem item. Error: \(error.localizedDescription)")
        })
    }

    /// Removes all items with the given domain identifier from the on-device index
    ///
    /// - Parameters:
    ///   - domain: the domain identifier
    ///
    @objc func deleteAllSearchableItemsFromDomain(_ domain: String) {
        deleteAllSearchableItemsFromDomains([domain])
    }

    /// Removes all items with the given domain identifiers from the on-device index
    ///
    /// - Parameters:
    ///   - domains: the domain identifiers
    ///
    @objc func deleteAllSearchableItemsFromDomains(_ domains: [String]) {
        guard !domains.isEmpty else {
            return
        }

        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: domains, completionHandler: { (error: Error?) -> Void in
            guard let error = error else {
                return
            }
            DDLogError("Could not delete CSSearchableItem items for domains: \(domains.joined(separator: ", ")). Error: \(error.localizedDescription)")
        })
    }

    /// Removes *all* items from the on-device index.
    ///
    /// Note: Be careful, this clears the entire index!
    ///
    @objc func deleteAllSearchableItems() {
        CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: { (error: Error?) -> Void in
            guard let error = error else {
                return
            }
            DDLogError("Could not delete all CSSearchableItem items. Error: \(error.localizedDescription)")
        })
    }

    // MARK: - NSUserActivity Handling

    /// Handle a NSUserAcitivity
    ///
    /// - Parameter activity: NSUserActivity that opened the app
    /// - Returns: true if it was handled correctly and activitytype was `CSSearchableItemActionType`, otherwise false
    ///
    @discardableResult
    @objc func handle(activity: NSUserActivity?) -> Bool {
        guard activity?.activityType == CSSearchableItemActionType,
            let compositeIdentifier = activity?.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
                return false
        }

        let (itemType, domainString, identifier) = SearchIdentifierGenerator.decomposeFromUniqueIdentifier(compositeIdentifier)
        guard itemType == .abstractPost, let postID = NumberFormatter().number(from: identifier) else {
            // We are only handling posts for now.
            DDLogError("Search manager unable to open post - postID:\(identifier) siteID:\(domainString)")
            return false
        }

        if let siteID = validWPComSiteID(with: domainString) {
            fetchPost(postID, blogID: siteID, onSuccess: { [weak self] apost in
                self?.navigateToScreen(for: apost)
            }, onFailure: {
                DDLogError("Search manager unable to open post - postID:\(postID) siteID:\(siteID)")
            })
        } else {
            fetchSelfHostedPost(postID, blogXMLRpcString: domainString, onSuccess: { [weak self] apost in
                self?.navigateToScreen(for: apost, isDotCom: false)
            }, onFailure: {
                DDLogError("Search manager unable to open self hosted post - postID:\(postID) xmlrpc:\(domainString)")
            })
        }
        return true
    }
}

// MARK: - Private Helpers

fileprivate extension SearchManager {
    func validWPComSiteID(with domainString: String) -> NSNumber? {
        return NumberFormatter().number(from: domainString)
    }

    // MARK: Fetching

    func fetchPost(_ postID: NSNumber,
                   blogID: NSNumber,
                   onSuccess: @escaping (_ post: AbstractPost) -> Void,
                   onFailure: @escaping () -> Void) {
        let context = ContextManager.sharedInstance().mainContext
        let blogService = BlogService(managedObjectContext: context)
        guard let blog = blogService.blog(byBlogId: blogID) else {
                onFailure()
                return
        }

        let postService = PostService(managedObjectContext: context)
        postService.getPostWithID(postID, for: blog, success: { apost in
            onSuccess(apost)
        }, failure: { error in
            onFailure()
        })
    }

    func fetchSelfHostedPost(_ postID: NSNumber,
                             blogXMLRpcString: String,
                             onSuccess: @escaping (_ post: AbstractPost) -> Void,
                             onFailure: @escaping () -> Void) {
        let context = ContextManager.sharedInstance().mainContext
        let blogService = BlogService(managedObjectContext: context)
        guard let selfHostedBlogs = blogService.blogsWithNoAccount() as? [Blog],
            let blog = selfHostedBlogs.filter({ $0.xmlrpc == blogXMLRpcString }).first else {
                onFailure()
                return
        }

        let postService = PostService(managedObjectContext: context)
        postService.getPostWithID(postID, for: blog, success: { apost in
            onSuccess(apost)
        }, failure: { error in
            onFailure()
        })
    }

    // MARK: Navigation

    func navigateToScreen(for apost: AbstractPost, isDotCom: Bool = true) {
        if let post = apost as? Post {
            self.navigateToScreen(for: post, isDotCom: isDotCom)
        } else if let page = apost as? Page {
            self.navigateToScreen(for: page, isDotCom: isDotCom)
        }
    }

    func navigateToScreen(for post: Post, isDotCom: Bool) {
        WPAppAnalytics.track(.spotlightSearchOpenedPost, with: post)
        let postIsPublishedOrScheduled = (post.status == .publish || post.status == .scheduled)
        if postIsPublishedOrScheduled && isDotCom {
            openReader(for: post, onFailure: {
                // If opening the reader fails, just open preview.
                openPreview(for: post)
            })
        } else if postIsPublishedOrScheduled {
            openPreview(for: post)
        } else {
            openEditor(for: post)
        }
    }

    func navigateToScreen(for page: Page, isDotCom: Bool) {
        WPAppAnalytics.track(.spotlightSearchOpenedPage, with: page)
        let pageIsPublishedOrScheduled = (page.status == .publish || page.status == .scheduled)
        if pageIsPublishedOrScheduled && isDotCom {
            openReader(for: page, onFailure: {
                // If opening the reader fails, just open preview.
                openPreview(for: page)
            })
        } else if pageIsPublishedOrScheduled {
            openPreview(for: page)
        } else {
            openEditor(for: page)
        }
    }

    func openListView(for apost: AbstractPost) {
        if let post = apost as? Post {
            WPTabBarController.sharedInstance().switchTabToPostsList(for: post)
        } else if let page = apost as? Page {
            WPTabBarController.sharedInstance().switchTabToPagesList(for: page)
        }
    }

    func openReader(for apost: AbstractPost, onFailure: () -> Void) {
        guard let postID = apost.postID,
            postID.intValue > 0,
            let blogID = apost.blog.dotComID else {
                onFailure()
                return
        }
        WPTabBarController.sharedInstance().showReaderTab(forPost: postID, onBlog: blogID)
    }

    func openEditor(for post: Post) {
        openListView(for: post)
        let editor = EditPostViewController.init(post: post)
        editor.modalPresentationStyle = .fullScreen
        WPTabBarController.sharedInstance().present(editor, animated: true, completion: nil)
    }

    func openEditor(for page: Page) {
        openListView(for: page)
        let editorSettings = EditorSettings()
        let postViewController = editorSettings.instantiatePageEditor(page: page) { (editor, vc) in
            editor.onClose = { changesSaved, _ in
                vc.dismiss(animated: true, completion: nil)
            }
        }

        let navController = UINavigationController(rootViewController: postViewController)
        navController.restorationIdentifier = Restorer.Identifier.navigationController.rawValue
        navController.modalPresentationStyle = .fullScreen
        WPTabBarController.sharedInstance().present(navController, animated: true, completion: nil)
    }

    func openPreview(for apost: AbstractPost) {
        openListView(for: apost)
        let previewController = PostPreviewViewController(post: apost)
        previewController.hidesBottomBarWhenPushed = true

        let navController = UINavigationController(rootViewController: previewController)
        navController.restorationIdentifier = Restorer.Identifier.navigationController.rawValue
        navController.modalPresentationStyle = .fullScreen
        previewController.onClose = {
            navController.dismiss(animated: true) {}
        }
        WPTabBarController.sharedInstance().present(navController, animated: true, completion: nil)
    }
}
