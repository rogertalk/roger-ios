import UIKit
import Crashlytics

class EditGroupViewController : UIViewController,
    UITextFieldDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    AvatarViewDelegate {

    @IBOutlet weak var addPhotoView: AvatarView!
    @IBOutlet weak var groupNameTextField: UITextField!
    @IBOutlet weak var createGroupButton: MaterialButton!

    var suggestedGroupTitle: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.addPhotoView.hasDropShadow = false
        self.addPhotoView.delegate = self
        self.addPhotoView.setText(NSLocalizedString("ADD\nPHOTO", comment: "Text on top of avatar with no photo in Settings"))
        self.addPhotoView.setTextColor(UIColor.black)
        self.addPhotoView.setFont(UIFont.rogerFontOfSize(11))
        self.addPhotoView.layer.borderColor = UIColor.darkGray.cgColor
        self.addPhotoView.layer.borderWidth = 2
        self.addPhotoView.shouldAnimate = false

        self.imagePicker.allowsEditing = true
        self.imagePicker.delegate = self

        self.groupNameTextField.delegate = self
        self.groupNameTextField.becomeFirstResponder()
        // Prefill group name if possible
        self.groupNameTextField.text = self.suggestedGroupTitle
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    @IBAction func createGroupTapped(_ sender: AnyObject) {
        guard let groupName = self.groupNameTextField.text , !groupName.isEmpty else {
            let alert = UIAlertController(title: NSLocalizedString("Oops!", comment: "Alert title"),
                                          message: NSLocalizedString("A group name is required.", comment: "Alert text"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Try again", comment: "Alert action"), style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }

        var image: Intent.Image?
        if let photo = self.groupImage, let imageData = UIImageJPEGRepresentation(photo, 0.8) {
            image = Intent.Image(format: .jpeg, data: imageData)
        }

        self.createGroupButton.startLoadingAnimation()
        // Aliases to search to find a stream on the backend.
        StreamService.instance.createStream(title: groupName, image: image) { stream, error in
            self.createGroupButton.stopLoadingAnimation()
            guard error == nil else {
                let alert = UIAlertController(title: NSLocalizedString("Oops!", comment: "Alert title"),
                                              message: NSLocalizedString("Something went wrong. Please try again!", comment: "Alert text"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }

            let streamDetails = self.storyboard?.instantiateViewController(withIdentifier: "StreamDetails") as! StreamDetailsViewController
            streamDetails.stream = stream
            self.navigationController?.pushViewControllerModal(streamDetails)
        }
        Answers.logCustomEvent(withName: "Create Group Confirmed", customAttributes:
            ["Group Name": groupName, "Has Image": image != nil])
    }

    @IBAction func backTapped(_ sender: AnyObject) {
        self.navigationController?.popViewControllerModal()
    }

    // MARK: - AvatarViewDelegate

    func didEndTouch(_ avatarView: AvatarView) {
        self.present(self.imagePicker, animated: true, completion: nil)
    }

    func accessibilityFocusChanged(_ avatarView: AvatarView, focused: Bool) { }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true, completion: nil)
        }

        guard let image = info[UIImagePickerControllerEditedImage] as? UIImage else {
            return
        }

        self.groupImage = image
        self.addPhotoView.setImage(image)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.createGroupTapped(self.createGroupButton)
        return false
    }

    // MARK: Private

    fileprivate let imagePicker = UIImagePickerController()
    fileprivate var groupImage: UIImage?
}
