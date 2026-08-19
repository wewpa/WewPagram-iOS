import Foundation
import UIKit

// Small trash-can silhouette shown next to the timestamp of a message that
// was deleted by the other side but archived locally. A tiny PNG (not an
// emoji), tinted white/template so it reads fine against the bubble's
// existing muted date-text color.
public enum WewDeletedGhostIcon {
    private static let base64 = "iVBORw0KGgoAAAANSUhEUgAAAB4AAAAeCAYAAAA7MK6iAAAAYklEQVR4nO2V0Q4AEAhF5f//+XplozQZq86zdVY3lPII0hwGALYY0Xa9qhFbEk88ZCJleCzrdiDeqP/IuMcy79n9jjdqv+LV++234xSLYs2nbiq+TYp9iLkF9dlxir8QP6MBOMMMQuY2+YkAAAAASUVORK5CYII="

    public static let image: UIImage? = {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data, scale: 3.0)?.withRenderingMode(.alwaysOriginal)
    }()
}
