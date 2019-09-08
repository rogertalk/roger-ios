import UIKit

protocol ServiceManager {
    var services: [Service] { get }

    func serviceLongPressed()
    func serviceTapped(_ index: Int)
}

class ServicesCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegate {

    var serviceManager: ServiceManager!

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.dataSource = self
        self.delegate = self
        self.delaysContentTouches = false
        // The collection view is currently too buggy for RTL.
        if #available(iOS 9.0, *) {
            self.semanticContentAttribute = .forceLeftToRight
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.serviceManager.services.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let service = self.serviceManager.services[(indexPath as NSIndexPath).row]

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ServiceCell.reuseIdentifier, for: indexPath) as! ServiceCell
        cell.titleLabel.text = service.title
        if let imageURL = service.imageURL {
            cell.iconImageView.af_setImage(withURL: imageURL)
        }
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = service.title
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.serviceManager.serviceTapped((indexPath as NSIndexPath).row)
    }

    // MARK: - Accessibility

    override func accessibilityElementCount() -> Int {
        return self.numberOfItems(inSection: 0)
    }

    override func accessibilityElement(at index: Int) -> Any? {
        return self.cellForItem(at: IndexPath(item: index, section: 0))
    }
}

class ServiceCell: UICollectionViewCell {
    static let reuseIdentifier = "serviceCell"

    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    override func prepareForReuse() {
        self.iconImageView.image = nil
        self.titleLabel.text = nil
    }
}
