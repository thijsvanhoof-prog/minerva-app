import Flutter
import UIKit

/// Flutter view controller die de statusbalk altijd licht (witte iconen) houdt op donkerblauwe achtergrond.
class MinervaFlutterViewController: FlutterViewController {
  override var preferredStatusBarStyle: UIStatusBarStyle {
    .lightContent
  }
}
