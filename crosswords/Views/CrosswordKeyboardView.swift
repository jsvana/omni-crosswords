//
//  CrosswordKeyboardView.swift
//  crosswords
//
//  The built-in keyboard, clue bar and clue list used by the compact and wide layouts.
//  The hidden text field stays first responder so a hardware keyboard keeps working;
//  these views feed the same delegate the system keyboard would.
//

import SwiftUI
import UIKit

/// Hands input from the SwiftUI keyboard to the text field's coordinator.
final class CrosswordInputRelay {
    weak var textField: NoActionTextField?

    private var coordinator: CrosswordTextFieldView.Coordinator? {
        return self.textField?.delegate as? CrosswordTextFieldView.Coordinator
    }

    func insert(_ letter: String) {
        guard let textField = self.textField else { return }
        _ = self.coordinator?.textField(
            textField, shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: letter)
    }

    func deleteBackward() {
        self.textField?.deleteBackward()
    }

    func toggleDirection() {
        guard let textField = self.textField else { return }
        self.coordinator?.pressToggleButton(textField: textField)
    }

    func goToNextClue() {
        guard let textField = self.textField else { return }
        self.coordinator?.goToNextClue(textField: textField)
    }

    func goToPreviousClue() {
        guard let textField = self.textField else { return }
        self.coordinator?.goToPreviousClue(textField: textField)
    }

    func solveCell() {
        guard let textField = self.textField else { return }
        self.coordinator?.solveCell(textField: textField)
    }

    func speakClue() {
        guard let textField = self.textField else { return }
        self.coordinator?.speakClue(textField: textField)
    }

    func tapClue() {
        guard let textField = self.textField else { return }
        self.coordinator?.tapClue(textField: textField)
    }
}

struct CrosswordKeyboardView: View {
    let inputRelay: CrosswordInputRelay
    var keyHeight: CGFloat

    private static let rows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]

    var body: some View {
        GeometryReader { proxy in
            let keyWidth = proxy.size.width / 10
            let sideKeyWidth = (proxy.size.width - keyWidth * 7) / 2
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(CrosswordKeyboardView.rows[0], id: \.self) { letter in
                        self.letterKey(letter, width: keyWidth)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(CrosswordKeyboardView.rows[1], id: \.self) { letter in
                        self.letterKey(letter, width: keyWidth)
                    }
                }
                HStack(spacing: 0) {
                    self.symbolKey(
                        "arrow.2.squarepath", label: "Toggle Direction", width: sideKeyWidth,
                        action: self.inputRelay.toggleDirection)
                    ForEach(CrosswordKeyboardView.rows[2], id: \.self) { letter in
                        self.letterKey(letter, width: keyWidth)
                    }
                    self.symbolKey(
                        "delete.left", label: "Delete", width: sideKeyWidth,
                        action: self.inputRelay.deleteBackward)
                }
            }
            .frame(width: proxy.size.width)
        }
        .frame(height: self.keyHeight * 3)
    }

    private func letterKey(_ letter: String, width: CGFloat) -> some View {
        Button(action: { self.inputRelay.insert(letter) }) {
            Text(letter)
                .font(.system(size: 20, weight: .medium))
        }
        .buttonStyle(KeyCapStyle(width: width, height: self.keyHeight, isAccessory: false))
    }

    private func symbolKey(_ systemName: String, label: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .accessibilityLabel(label)
        }
        .buttonStyle(KeyCapStyle(width: width, height: self.keyHeight, isAccessory: true))
    }
}

/// Draws the key cap inset from the button's frame, so the gaps between caps still register taps.
private struct KeyCapStyle: ButtonStyle {
    var width: CGFloat
    var height: CGFloat
    var isAccessory: Bool

    func makeBody(configuration: Configuration) -> some View {
        let restingColor = self.isAccessory ? UIColor.systemGray4 : UIColor.systemGray5
        configuration.label
            .foregroundStyle(Color(UIColor.label))
            .frame(width: max(0, self.width - 5), height: max(0, self.height - 6))
            .background(
                Color(configuration.isPressed ? UIColor.systemGray2 : restingColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .frame(width: self.width, height: self.height)
            .contentShape(Rectangle())
    }
}

/// One-line clue with previous/next buttons, used above the keyboard in the compact layout.
struct CrosswordClueBarView: View {
    let inputRelay: CrosswordInputRelay
    var clueID: String
    var clue: String
    var isSolutionAvailable: Bool
    @ObservedObject var userSettings: UserSettings

    var body: some View {
        HStack(spacing: 4) {
            self.barButton("chevron.left", label: "Previous Clue", action: self.inputRelay.goToPreviousClue)
            if self.userSettings.actionButtonsInToolbar && self.isSolutionAvailable {
                self.barButton("lifepreserver", label: "Solve Cell", action: self.inputRelay.solveCell)
            }
            Button(action: self.inputRelay.tapClue) {
                CrosswordClueText(clueID: self.clueID, clue: self.clue, fontSize: self.clueFontSize)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if self.userSettings.speakClueButton {
                self.barButton("speaker.3.fill", label: "Speak Clue", action: self.inputRelay.speakClue)
            }
            self.barButton("chevron.right", label: "Next Clue", action: self.inputRelay.goToNextClue)
        }
        .padding(.horizontal, 4)
        .frame(height: CGFloat(Constants.keybordToolbarHeight) + 4)
        .background(Color(UIColor.systemGray6))
    }

    private var clueFontSize: CGFloat {
        return CGFloat(max(13, self.userSettings.clueSize))
    }

    private func barButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .accessibilityLabel(label)
                .frame(width: 36, height: CGFloat(Constants.keybordToolbarHeight))
                .contentShape(Rectangle())
        }
    }
}

/// A clue rendered with its number in front. Clues may carry markdown emphasis.
struct CrosswordClueText: View {
    var clueID: String
    var clue: String
    var fontSize: CGFloat

    var body: some View {
        Text(self.attributedClue)
            .font(.system(size: self.fontSize))
    }

    private var attributedClue: AttributedString {
        var number = AttributedString(self.clueID + "  ")
        number.inlinePresentationIntent = .stronglyEmphasized
        let text = (try? AttributedString(markdown: self.clue)) ?? AttributedString(self.clue)
        return number + text
    }
}

/// The current clue as a card, used at the top of the side panel in the wide layout.
struct CrosswordClueCardView: View {
    let inputRelay: CrosswordInputRelay
    var clueID: String
    var clue: String
    var isSolutionAvailable: Bool
    @ObservedObject var userSettings: UserSettings

    var body: some View {
        HStack(spacing: 0) {
            self.cardButton("chevron.left", label: "Previous Clue", action: self.inputRelay.goToPreviousClue)
            Button(action: self.inputRelay.tapClue) {
                VStack(spacing: 2) {
                    Text(CrosswordClueListView.title(for: self.clueID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((try? AttributedString(markdown: self.clue)) ?? AttributedString(self.clue))
                        .font(.system(size: CGFloat(max(15, self.userSettings.clueSize + 2)), weight: .medium))
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if self.userSettings.speakClueButton {
                self.cardButton("speaker.3.fill", label: "Speak Clue", action: self.inputRelay.speakClue)
            }
            if self.userSettings.actionButtonsInToolbar && self.isSolutionAvailable {
                self.cardButton("lifepreserver", label: "Solve Cell", action: self.inputRelay.solveCell)
            }
            self.cardButton("chevron.right", label: "Next Clue", action: self.inputRelay.goToNextClue)
        }
        .frame(height: 76)
        .background(Color(UIColor.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func cardButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .accessibilityLabel(label)
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
}

/// Every clue, across then down. Tapping one moves the cursor to it.
struct CrosswordClueListView: View {
    @ObservedObject var crossword: Crossword
    var currentClueID: String
    var notes: String
    var fontSize: CGFloat
    var onSelect: (String) -> Void

    @State private var acrossClueIDs: [String] = []
    @State private var downClueIDs: [String] = []

    var body: some View {
        ScrollViewReader { scrollReader in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !self.notes.isEmpty {
                        Text(self.notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    self.section(title: "Across", clueIDs: self.acrossClueIDs)
                    self.section(title: "Down", clueIDs: self.downClueIDs)
                }
            }
            .onChange(of: self.currentClueID) { _, newClueID in
                if !newClueID.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollReader.scrollTo(newClueID, anchor: .center)
                    }
                }
            }
        }
        .onAppear(perform: self.loadClueIDs)
    }

    private func section(title: String, clueIDs: [String]) -> some View {
        Section {
            ForEach(clueIDs, id: \.self) { clueID in
                self.row(clueID)
            }
        } header: {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.systemBackground))
        }
    }

    private func row(_ clueID: String) -> some View {
        let isCurrent = clueID == self.currentClueID
        let clue = self.crossword.clues?[clueID] ?? ""
        return Button(action: { self.onSelect(clueID) }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(clueID.dropLast()))
                    .font(.system(size: self.fontSize, weight: .semibold))
                    .frame(width: self.fontSize * 2, alignment: .trailing)
                Text((try? AttributedString(markdown: clue)) ?? AttributedString(clue))
                    .font(.system(size: self.fontSize))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(self.isFilled(clueID) && !isCurrent ? Color.secondary : Color(UIColor.label))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isCurrent ? Color(UIColor.systemBlue).opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(clueID)
    }

    private func isFilled(_ clueID: String) -> Bool {
        guard let tags = self.crossword.clueToTagsMap?[clueID], let entry = self.crossword.entry else {
            return false
        }
        return tags.allSatisfy { tag in
            tag >= 0 && tag < entry.count && !entry[tag].isEmpty
        }
    }

    private func loadClueIDs() {
        let clueIDs = Array((self.crossword.clues ?? [:]).keys)
        self.acrossClueIDs = CrosswordClueListView.sorted(clueIDs.filter { $0.hasSuffix("A") })
        self.downClueIDs = CrosswordClueListView.sorted(clueIDs.filter { $0.hasSuffix("D") })
    }

    private static func sorted(_ clueIDs: [String]) -> [String] {
        return clueIDs.sorted { lhs, rhs in
            (Int(lhs.dropLast()) ?? 0) < (Int(rhs.dropLast()) ?? 0)
        }
    }

    static func title(for clueID: String) -> String {
        if clueID.isEmpty {
            return ""
        }
        let direction = clueID.hasSuffix("A") ? "Across" : "Down"
        return String(clueID.dropLast()) + " " + direction
    }
}
