import UIKit
import XADisplayProtocol

final class MediaRemoteViewController: UIViewController {
    var onCommand: ((MediaAction, Double) -> Void)?
    var onClose: (() -> Void)?
    private let appLabel = UILabel()
    private let detailLabel = UILabel()
    private let noteLabel = UILabel()
    private var lastScrub = 0.5

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        appLabel.textColor = .white
        appLabel.font = UIFont.systemFont(ofSize: 36, weight: .bold)
        appLabel.textAlignment = .center
        appLabel.numberOfLines = 2
        appLabel.text = "Mac"
        detailLabel.textColor = UIColor(white: 0.75, alpha: 1)
        detailLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 2
        detailLabel.text = "Frontmost app"
        noteLabel.textColor = UIColor(white: 0.55, alpha: 1)
        noteLabel.font = UIFont.systemFont(ofSize: 14)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        noteLabel.text = NowPlayingSource.note
        let close = button("Close")
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let play = button("Play / Pause")
        play.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        let previous = button("Previous")
        previous.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        let next = button("Next")
        next.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        let down = button("Volume −")
        down.addTarget(self, action: #selector(volumeDown), for: .touchUpInside)
        let up = button("Volume +")
        up.addTarget(self, action: #selector(volumeUp), for: .touchUpInside)
        let scrub = UISlider()
        scrub.minimumValue = 0
        scrub.maximumValue = 1
        scrub.value = 0.5
        scrub.addTarget(self, action: #selector(scrubbed(_:)), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [close, appLabel, detailLabel, noteLabel, play, previous, next, down, up, scrub])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func show(_ info: XANowPlaying) {
        appLabel.text = info.appName.isEmpty ? "Mac" : info.appName
        if info.hasPublicMetadata {
            detailLabel.text = [info.title, info.artist].filter { !$0.isEmpty }.joined(separator: " · ")
        } else {
            detailLabel.text = "Frontmost app"
        }
    }

    private func button(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        button.backgroundColor = UIColor(white: 0.16, alpha: 1)
        button.layer.cornerRadius = 10
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return button
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func playTapped() { onCommand?(.playPause, 0) }
    @objc private func previousTapped() { onCommand?(.previous, 0) }
    @objc private func nextTapped() { onCommand?(.next, 0) }
    @objc private func volumeDown() { onCommand?(.volumeDown, 0) }
    @objc private func volumeUp() { onCommand?(.volumeUp, 0) }

    @objc private func scrubbed(_ sender: UISlider) {
        let value = Double(sender.value)
        let delta = value - lastScrub
        lastScrub = 0.5
        sender.value = 0.5
        guard abs(delta) > 0.04 else { return }
        onCommand?(delta > 0 ? .seekForward : .seekBackward, delta)
    }
}

final class MacPickerViewController: UITableViewController {
    var saved: [SavedMac] = []
    var discovered: [String] = []
    var onSelectSaved: ((SavedMac) -> Void)?
    var onSelectDiscovered: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Macs"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    @objc private func done() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = section == 0 ? discovered.count : saved.count
        return max(count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Nearby" : "Saved"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 ? WakeOnDemandPolicy.summary : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.numberOfLines = 2
        if indexPath.section == 0 {
            cell.textLabel?.text = discovered.isEmpty ? "No Mac hosts advertising yet" : discovered[indexPath.row]
        } else if saved.isEmpty {
            cell.textLabel?.text = "No saved Macs"
        } else {
            let mac = saved[indexPath.row]
            cell.textLabel?.text = mac.name
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, indexPath.row < discovered.count {
            onSelectDiscovered?(discovered[indexPath.row])
        } else if indexPath.section == 1, indexPath.row < saved.count {
            onSelectSaved?(saved[indexPath.row])
        }
        dismiss(animated: true)
    }
}
