import UIKit
import UserNotifications
import UserNotificationsUI

@objc(NotificationViewController)
class NotificationViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.groupTableViewBackground
    }
}

extension NotificationViewController: UNNotificationContentExtension {
    func didReceive(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo

        guard let subjectData = userInfo["attributedSubjectData"] as? Data else { return }

        let subjectDecodingAttributes: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        let roundTripHtml = try? NSAttributedString(data: subjectData, options: subjectDecodingAttributes, documentAttributes: nil)
        debugPrint(#function + " : \(String(describing: roundTripHtml))")
    }
}
