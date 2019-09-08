import UIKit

class MaterialTextField: UITextField {

    override func awakeFromNib() {
        self.layoutIfNeeded()

        let clearButton = UIButton(frame: CGRect(x: 0, y: 0, width: self.frame.height, height: self.frame.height))
        clearButton.titleLabel!.font = UIFont(name: "MaterialIcons-Regular", size: 24)
        clearButton.setTitle("clear", for: .normal)
        clearButton.setTitleColor(UIColor(white: 0.447, alpha: 1), for: .normal)
        clearButton.addTarget(self, action: #selector(MaterialTextField.clearClicked), for: .touchUpInside)
        clearButton.isHidden = true

        self.clearButtonMode = .never
        self.rightView = clearButton
        self.rightViewMode = .always
        self.rightView?.isHidden = true

        self.addTarget(self, action: #selector(MaterialTextField.editingDidBegin), for: .editingDidBegin)
        self.addTarget(self, action: #selector(MaterialTextField.editingChanged), for: .editingChanged)
    }

    func clearClicked() {
        self.text = ""
        self.sendActions(for: .editingChanged)
        self.becomeFirstResponder()
    }

    func editingChanged() {
        self.rightView!.isHidden = self.text == nil || self.text == ""
    }

    func editingDidBegin() {
        self.rightView!.isHidden = self.text == nil || self.text == ""
    }
}
