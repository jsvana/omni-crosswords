//
//  CrosswordView.swift
//  crosswords
//
//  Created by Rohan Narayan on 7/20/20.
//  Copyright © 2020 Rohan Narayan. All rights reserved.
//

import AVFoundation
import CoreData
import SwiftUI

struct CrosswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.windowSize) private var windowSize

    @ObservedObject var crossword: Crossword
    @ObservedObject var userSettings: UserSettings
    @StateObject var keyboardHeightHelper = KeyboardHeightHelper()
    @State var synthesizer = AVSpeechSynthesizer()

    @State var focusedTag: Int = -1
    @State var highlighted: [Int] = Array()
    @State var goingAcross: Bool = true
    @State var isErrorTrackingEnabled: Bool = false
    @State var forceUpdate = false
    @State var becomeFirstResponder: Bool = false
    @State var boxWidth: CGFloat = 0.0
    @State var viewWidth: CGFloat = 0.0
    // space the grid may fill in the compact and wide layouts
    @State var gridAreaSize: CGSize = .zero
    @State var topSafeAreaInset: CGFloat = 0.0
    @State var inputRelay = CrosswordInputRelay()

    @State var isZoomed: Bool = false
    @State var isRebusMode: Bool = false
    @State var isPaused: Bool = false

    // height of components. does not include keyboard height
    var componentHeights: CGFloat {
        let crosswordHeight = self.getInitialBoxWidth() * CGFloat(self.crossword.height)
        // the top inset covers the status bar and, when it is showing, the navigation bar
        let barHeights: CGFloat = CGFloat(Constants.keybordToolbarHeight) + self.topSafeAreaInset

        return barHeights + crosswordHeight - 10
    }

    var displayTitle: String {
        let date = self.crossword.date ?? Date.init(timeIntervalSinceNow: TimeInterval(0))
        var prefix: String = ""
        if self.crossword.solved {
            prefix = "Solved: "
        }
        return prefix + self.crossword.outletName! + " - " + TimeUtils.toSmallDateFormat(date)
    }

    var layoutMode: CrosswordLayoutMode {
        return CrosswordLayoutMode.forWindow(self.windowSize)
    }

    var currentClueID: String {
        return CrosswordUtils.getClueID(tag: self.focusedTag, crossword: self.crossword, goingAcross: self.goingAcross)
    }

    var currentClue: String {
        return CrosswordUtils.getClue(focusedTag: self.focusedTag, crossword: self.crossword, goingAcross: self.goingAcross)
    }

    init(crossword: Crossword, userSettings: UserSettings) {
        self.crossword = crossword
        self.userSettings = userSettings
        self._isErrorTrackingEnabled = State(
            initialValue:
                CrosswordUtils.isSolutionAvailable(crossword: crossword)
                ? self.userSettings.defaultErrorTracking
                : false)
    }

    var body: some View {
        Group {
            switch self.layoutMode {
            case .standard:
                self.standardBody
            case .compact:
                self.compactBody
            case .wide:
                self.wideBody
            }
        }
        .overlay(alignment: .bottom, content: self.maybePauseScreen)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded({ value in
                    if value.translation.width < 0 && self.focusedTag != -1 {
                        // left
                        ChangeFocusUtils.goToPreviousClue(
                            focusedTag: self.$focusedTag,
                            crossword: self.crossword,
                            userSettings: self.userSettings,
                            goingAcross: self.$goingAcross,
                            isHighlighted: self.$highlighted)
                    }

                    if value.translation.width > 0 && self.focusedTag != -1 {
                        // right
                        ChangeFocusUtils.goToNextClue(
                            focusedTag: self.$focusedTag,
                            crossword: self.crossword,
                            userSettings: self.userSettings,
                            goingAcross: self.$goingAcross,
                            isHighlighted: self.$highlighted)
                    }
                })
        )
        .toolbar(self.showCustomToolbar() || self.layoutMode != .standard ? .hidden : .automatic)
        .navigationBarTitle(Text(verbatim: self.displayTitle), displayMode: .inline)
        .navigationBarColor(self.crossword.solved ? .systemGreen : .systemBackground)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CrosswordViewLeadingToolbarView(goBack: self.goBack)
            }
            .hideSharedBackgroundIfAvailable()

            ToolbarItemGroup(placement: .topBarTrailing) {
                CrosswordSettingsToolbarButtonView(
                    crosswordTitle: self.crossword.title!, author: self.crossword.author!, notes: self.crossword.notes!,
                    copyright: self.crossword.copyright!, isSolved: self.crossword.solved, outletName: self.crossword.outletName!,
                    isSolutionAvailable: CrosswordUtils.isSolutionAvailable(crossword: self.crossword), showSettings: self.showSettings,
                    showSolution: self.showSolution,
                    getProgressPercentage: { () -> CGFloat in
                        CrosswordUtils.getCrosswordProgress(self.crossword)
                    }, markAsSolved: self.markAsSolved, isErrorTrackingEnabled: self.$isErrorTrackingEnabled,
                    errorTrackingEnablementSideEffect: self.errorTrackingEnablementSideEffect)

                ShareCrosswordToolbarButtonView(getShareMessage: self.getShareMessage, isSolved: self.crossword.solved)
            }
            .hideSharedBackgroundIfAvailable()
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newValue in
                    if abs(self.viewWidth - newValue) > 1 {
                        self.viewWidth = newValue
                    }
                    if !self.isZoomed && self.layoutMode == .standard {
                        self.boxWidth = self.getInitialBoxWidth()
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.safeAreaInsets.top
                } action: { newValue in
                    self.topSafeAreaInset = newValue
                }
        }
        .onChange(of: self.layoutMode) { _, _ in
            // folding or unfolding swaps the layout, so start it unzoomed at its own cell size
            self.isZoomed = false
            self.boxWidth = self.getInitialBoxWidth()
        }
        .onAppear(perform: self.applyDebugLaunchArguments)
        // custom back button added in leading toolbar view
        .navigationBarBackButtonHidden(true)
    }

    func showCustomToolbar() -> Bool {
        // If it's a phone with a tall window, use the custom toolbar.
        // Short windows (a closed Duo, the smallest phones) get the compact layout instead.
        return self.horizontalSizeClass == .compact && self.windowSize.height > Constants.customToolbarMinWindowHeight
    }

    var customToolbar: some View {
        HStack {
            CrosswordViewLeadingToolbarView(goBack: self.goBack)
                .padding(.leading)
            Spacer()
            Text(verbatim: self.displayTitle)
                .bold()
            Spacer()
            HStack {
                CrosswordSettingsToolbarButtonView(
                    crosswordTitle: self.crossword.title!, author: self.crossword.author!, notes: self.crossword.notes!,
                    copyright: self.crossword.copyright!, isSolved: self.crossword.solved, outletName: self.crossword.outletName!,
                    isSolutionAvailable: CrosswordUtils.isSolutionAvailable(crossword: self.crossword), showSettings: self.showSettings,
                    showSolution: self.showSolution,
                    getProgressPercentage: { () -> CGFloat in
                        CrosswordUtils.getCrosswordProgress(self.crossword)
                    }, markAsSolved: self.markAsSolved, isErrorTrackingEnabled: self.$isErrorTrackingEnabled,
                    errorTrackingEnablementSideEffect: self.errorTrackingEnablementSideEffect)

                ShareCrosswordToolbarButtonView(getShareMessage: self.getShareMessage, isSolved: self.crossword.solved)
            }
            .padding(.trailing)
        }
    }

    var standardBody: some View {
        VStack {
            if self.showCustomToolbar() {
                self.customToolbar
                    .background(self.crossword.solved ? .green : Color(UIColor.systemBackground))
            }

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ScrollViewReader { scrollreader in
                    CrosswordGridView(
                        crossword: self.crossword, boxWidth: self.boxWidth,
                        getViewWidth: { self.viewWidth }, synthesizer: self.synthesizer,
                        userSettings: self.userSettings,
                        isErrorTrackingEnabled: self.$isErrorTrackingEnabled,
                        focusedTag: self.$focusedTag,
                        highlighted: self.$highlighted,
                        goingAcross: self.$goingAcross,
                        forceUpdate: self.$forceUpdate,
                        becomeFirstResponder: self.$becomeFirstResponder,
                        isRebusMode: self.$isRebusMode,
                    )
                    .onChange(of: self.focusedTag) { _, newFocusedTag in
                        if self.isZoomed {
                            scrollreader.scrollTo("cell" + String(newFocusedTag))
                            return
                        } else if newFocusedTag >= 0 && self.shouldScroll() {
                            let newRowNumber = CrosswordUtils.getRowNumberFromTag(
                                tag: newFocusedTag,
                                crossword:
                                    self.crossword)
                            scrollreader.scrollTo("row" + String(newRowNumber), anchor: .center)
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .safeAreaPadding(.horizontal, max(0, (self.viewWidth - self.boxWidth * CGFloat(self.crossword.length)) / 2))
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            //.background(.random)

            if self.focusedTag != -1 {
                CrosswordFooter(
                    zoom: self.zoom,
                    isZoomed: self.isZoomed,
                    isPaused: self.isPaused,
                    pause: self.pause,
                    solveCell: self.solveCell,
                    isSolved: self.crossword.solved,
                    solvedTime: Int(self.crossword.solvedTime),
                    isRebusMode: self.$isRebusMode,
                    userSettings: self.userSettings
                )
                .padding(.horizontal, 10)
            }

            Spacer()

            if self.focusedTag == -1 {
                VStack(alignment: .center) {
                    Text(self.crossword.title!)
                    Text(self.crossword.author!)
                    if self.crossword.notes != nil && !self.crossword.notes!.isEmpty {
                        Text(self.crossword.notes!)
                    }
                    Text(self.crossword.copyright!)
                }
                .multilineTextAlignment(.center)
            }
            if ProcessInfo.processInfo.isiOSAppOnMac {
                // they have a hardware keyboard, so artificially create space at the bottom
                // this is becuase the scrollview pushes the timer row to below the toolbar only on macOS
                Divider()
                    .frame(height: CGFloat(Constants.keybordToolbarHeight))
            }
        }
    }

    // MARK: - Compact and wide layouts

    /// Short, narrow window: toolbar, the whole grid, then the clue bar and built-in keyboard.
    var compactBody: some View {
        VStack(spacing: 0) {
            self.customToolbar
                .padding(.vertical, 4)
                .background(self.crossword.solved ? .green : Color(UIColor.systemBackground))
            self.fittedGridScrollView
            VStack(spacing: 4) {
                self.footerRow
                CrosswordClueBarView(
                    inputRelay: self.inputRelay, clueID: self.currentClueID, clue: self.currentClue,
                    isSolutionAvailable: CrosswordUtils.isSolutionAvailable(crossword: self.crossword),
                    userSettings: self.userSettings)
                CrosswordKeyboardView(inputRelay: self.inputRelay, keyHeight: Constants.compactKeyHeight)
                    .padding(.horizontal, 2)
            }
            // keep the space reserved while nothing is selected so the grid does not resize
            .opacity(self.focusedTag == -1 ? 0 : 1)
            .allowsHitTesting(self.focusedTag != -1)
            .overlay {
                if self.focusedTag == -1 {
                    ScrollView(.vertical) {
                        self.crosswordInfo
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }

    /// Short, wide window: the grid fills the height, clues and the built-in keyboard sit beside it.
    var wideBody: some View {
        HStack(spacing: 0) {
            self.fittedGridScrollView
                .padding(.vertical, 6)
                .padding(.leading, 6)
            VStack(spacing: 8) {
                self.customToolbar
                    .padding(.top, 6)
                if self.focusedTag != -1 {
                    CrosswordClueCardView(
                        inputRelay: self.inputRelay, clueID: self.currentClueID, clue: self.currentClue,
                        isSolutionAvailable: CrosswordUtils.isSolutionAvailable(crossword: self.crossword),
                        userSettings: self.userSettings)
                } else {
                    self.crosswordInfo
                        .font(.footnote)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                }
                CrosswordClueListView(
                    crossword: self.crossword, currentClueID: self.currentClueID,
                    notes: self.crossword.notes ?? "",
                    fontSize: CGFloat(max(13, self.userSettings.clueSize)),
                    onSelect: self.selectClue)
                self.footerRow
                CrosswordKeyboardView(inputRelay: self.inputRelay, keyHeight: Constants.wideKeyHeight)
                    .opacity(self.focusedTag == -1 ? 0.35 : 1)
                    .allowsHitTesting(self.focusedTag != -1)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 10)
            .frame(width: self.sidePanelWidth)
        }
    }

    var sidePanelWidth: CGFloat {
        return min(400, max(340, self.windowSize.width * 0.4))
    }

    /// The footer starts and stops the timer as it comes and goes, so it only exists while a cell is selected.
    @ViewBuilder
    var footerRow: some View {
        if self.focusedTag != -1 {
            CrosswordFooter(
                zoom: self.zoom,
                isZoomed: self.isZoomed,
                isPaused: self.isPaused,
                pause: self.pause,
                solveCell: self.solveCell,
                isSolved: self.crossword.solved,
                solvedTime: Int(self.crossword.solvedTime),
                isRebusMode: self.$isRebusMode,
                userSettings: self.userSettings
            )
            .padding(.horizontal, 10)
            .frame(height: Constants.footerHeight)
        } else {
            Color.clear
                .frame(height: Constants.footerHeight)
        }
    }

    var crosswordInfo: some View {
        VStack(alignment: .center) {
            Text(self.crossword.title!)
            Text(self.crossword.author!)
            if self.layoutMode != .wide && self.crossword.notes != nil && !self.crossword.notes!.isEmpty {
                Text(self.crossword.notes!)
            }
            Text(self.crossword.copyright!)
        }
        .multilineTextAlignment(.center)
    }

    /// The grid sized to fit the space it is given, centered in it. It only scrolls when zoomed
    /// or when fitting the whole grid would make the cells too small to tap.
    var fittedGridScrollView: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ScrollViewReader { scrollreader in
                CrosswordGridView(
                    crossword: self.crossword, boxWidth: self.boxWidth,
                    getViewWidth: { self.viewWidth }, synthesizer: self.synthesizer,
                    userSettings: self.userSettings,
                    isErrorTrackingEnabled: self.$isErrorTrackingEnabled,
                    focusedTag: self.$focusedTag,
                    highlighted: self.$highlighted,
                    goingAcross: self.$goingAcross,
                    forceUpdate: self.$forceUpdate,
                    becomeFirstResponder: self.$becomeFirstResponder,
                    isRebusMode: self.$isRebusMode,
                    useSystemKeyboard: false,
                    inputRelay: self.inputRelay
                )
                .onChange(of: self.focusedTag) { _, newFocusedTag in
                    if newFocusedTag < 0 {
                        return
                    }
                    if self.isZoomed {
                        scrollreader.scrollTo("cell" + String(newFocusedTag))
                    } else {
                        let newRowNumber = CrosswordUtils.getRowNumberFromTag(tag: newFocusedTag, crossword: self.crossword)
                        scrollreader.scrollTo("row" + String(newRowNumber), anchor: .center)
                    }
                }
                .scrollTargetLayout()
                .frame(minWidth: self.gridAreaSize.width, minHeight: self.gridAreaSize.height)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            self.gridAreaSize = newValue
            if !self.isZoomed {
                self.boxWidth = self.fittedBoxWidth(in: newValue)
            }
        }
    }

    func fittedBoxWidth(in area: CGSize) -> CGFloat {
        if area.width <= 0 || area.height <= 0 || self.crossword.length <= 0 || self.crossword.height <= 0 {
            return 0
        }
        let widthFit = area.width / CGFloat(self.crossword.length)
        // the hidden text field under the grid takes one point
        let heightFit = (area.height - 1) / CGFloat(self.crossword.height)
        let fit = min(widthFit, heightFit)
        if self.layoutMode == .wide {
            return min(fit, Constants.maxWideCellSize)
        }
        let maxInitialSize = CGFloat(Constants.maxInitialCellSize)
        if fit >= Constants.minFittedCellSize {
            return min(fit, maxInitialSize)
        }
        // too small to tap when fitted: fill the width and scroll vertically instead
        return min(widthFit, maxInitialSize)
    }

    func selectClue(_ clueID: String) {
        guard let tags = self.crossword.clueToTagsMap?[clueID], let firstTag = tags.first else {
            return
        }
        let firstEmptyTag = tags.first { tag in
            self.crossword.entry?[safe: tag]?.isEmpty ?? false
        }
        self.isRebusMode = false
        if !self.becomeFirstResponder {
            self.becomeFirstResponder = true
        }
        self.goingAcross = clueID.hasSuffix("A")
        ChangeFocusUtils.changeFocus(
            tag: firstEmptyTag ?? firstTag, crossword: self.crossword,
            goingAcross: self.$goingAcross, focusedTag: self.$focusedTag,
            isHighlighted: self.$highlighted)
    }

    func applyDebugLaunchArguments() {
        #if DEBUG
            // `-focusClue 17A` selects a clue on open, for screenshots without touch input
            if let clueID = UserDefaults.standard.string(forKey: "focusClue") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.selectClue(clueID)
                }
                // `-typeText ABC` then presses those keys on the built-in keyboard
                if let text = UserDefaults.standard.string(forKey: "typeText") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        for letter in text {
                            self.inputRelay.insert(String(letter))
                        }
                    }
                }
            }
        #endif
    }

    func getShareMessage() -> String {
        var shareMessageLines: [String] = Array()
        let title = self.crossword.outletName! + " " + TimeUtils.toSmallDateFormat(self.crossword.date!)
        shareMessageLines.append("🧩 \(title)")
        if !self.crossword.solved {
            let progressBarSize = 6
            var progressBar = String(repeating: "░", count: progressBarSize)
            let filledSize = Int(Double(progressBarSize) * CrosswordUtils.getCrosswordProgress(self.crossword))
            let filledInBar = String(repeating: "█", count: filledSize)

            let range = progressBar.startIndex..<progressBar.index(progressBar.startIndex, offsetBy: filledSize)
            progressBar.replaceSubrange(range, with: filledInBar)
            shareMessageLines.append("⏳ Progress: [\(progressBar)]")
        }
        if self.crossword.solvedTime > 0 {
            let prefix: String = self.crossword.solved ? "⏱️ Solve Time: " : "⏱️ Time: "
            shareMessageLines.append(prefix + TimeUtils.toDisplayTime(Int(self.crossword.solvedTime)))
        }
        let helpUsed: Int? = CrosswordUtils.getHelpUsed(self.crossword)
        if helpUsed != nil {
            shareMessageLines.append("💡 Help Used: \(helpUsed!)")
        }
        shareMessageLines.append("🔲 Omni Crosswords")

        return shareMessageLines.joined(separator: "\n")
    }

    func getInitialBoxWidth() -> CGFloat {
        if self.layoutMode != .standard {
            return self.fittedBoxWidth(in: self.gridAreaSize)
        }
        let maxInitialSize: CGFloat = CGFloat(Constants.maxInitialCellSize)
        let defaultSize: CGFloat = self.viewWidth / CGFloat(self.crossword.length)
        return min(defaultSize, maxInitialSize)
    }

    func zoom() {
        self.isZoomed.toggle()
        let initialWidth = self.getInitialBoxWidth()
        self.boxWidth =
            self.isZoomed
            ? initialWidth * CGFloat(self.userSettings.zoomMagnificationLevel)
            : initialWidth
    }

    func shouldScroll() -> Bool {
        let navigationBarHeight = self.showCustomToolbar() ? Constants.crosswordToolbarButtonSize : Constants.navigationBarHeight
        let componentHeights =
            self.componentHeights + navigationBarHeight
            + self.keyboardHeightHelper.keyboardHeight
        return componentHeights > self.windowSize.height
    }

    func showSolution() {
        for tag in (0..<self.crossword.entry!.count) {
            if self.crossword.helpTracking?[tag] == nil || self.crossword.helpTracking![tag] {
                continue
            }
            if self.crossword.entry![tag] != self.crossword.solution![tag] {
                self.crossword.helpTracking![tag] = true
            }
        }
        self.crossword.entry = self.crossword.solution
        self.forceUpdate.toggle()
        CrosswordUtils.solutionHandler(
            crossword: self.crossword, shouldAddStatistics: false,
            userSettings: self.userSettings, focusedTag: self.$focusedTag,
            becomeFirstResponder: self.$becomeFirstResponder,
            isHighlighted: self.$highlighted, timerWrapper: nil,
            managedObjectContext: self.managedObjectContext)
    }

    func errorTrackingEnablementSideEffect() {
        for tag in (0..<self.crossword.entry!.count) {
            if self.crossword.helpTracking?[tag] == nil || self.crossword.helpTracking![tag] {
                continue
            }
            if !self.crossword.entry![tag].isEmpty
                && self.crossword.entry![tag] != self.crossword.solution![tag]
            {
                self.crossword.helpTracking![tag] = true
            }
        }
        self.forceUpdate.toggle()
        CrosswordUtils.saveGame(crossword: self.crossword, userSettings: self.userSettings)
    }

    func markAsSolved() {
        if CrosswordUtils.isSolutionAvailable(crossword: self.crossword)
            || CrosswordUtils.getCrosswordProgress(self.crossword) != 1.0
        {
            // should only call this method if the solution is not available and the crossword is complete
            return
        }
        CrosswordUtils.solutionHandler(
            crossword: self.crossword, shouldAddStatistics: false,
            shouldCheckSolution: false, userSettings: self.userSettings,
            focusedTag: self.$focusedTag,
            becomeFirstResponder: self.$becomeFirstResponder,
            isHighlighted: self.$highlighted, timerWrapper: nil,
            managedObjectContext: self.managedObjectContext)
    }

    func showSettings() {
        self.becomeFirstResponder = false
        self.focusedTag = -1
        self.highlighted = Array()
    }

    func goBack() {
        self.becomeFirstResponder = false
        DispatchQueue.main.async {
            self.dismiss()
        }
    }

    func pause() {
        self.becomeFirstResponder = false
        self.focusedTag = -1
        self.highlighted = Array()
        self.isPaused = true
    }

    func solveCell(timerWrapper: TimerWrapper) {
        self.isRebusMode = false
        CrosswordUtils.solveCell(
            tag: self.focusedTag,
            crossword: self.crossword,
            userSettings: self.userSettings,
            focusedTag: self.$focusedTag,
            becomeFirstResponder: self.$becomeFirstResponder,
            goingAcross: self.$goingAcross,
            isHighlighted: self.$highlighted,
            timerWrapper: timerWrapper,
            managedObjectContext: self.managedObjectContext
        )
    }

    @ViewBuilder
    func maybePauseScreen() -> some View {
        if self.isPaused {
            VStack {
                Text(TimeUtils.toDisplayTime(Int(self.crossword.solvedTime)))
                    .font(.system(size: 30))
                    .padding(.bottom)
                Button(action: { self.isPaused.toggle() }) {
                    Image(systemName: "play.fill")
                        .accessibilityLabel("Resume")
                        .font(.system(size: 30))
                        .tint(Color(UIColor.label))
                }
            }
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: 0,
                maxHeight: self.layoutMode == .standard ? self.windowSize.height - 120 : .infinity
            )
            .background(.ultraThinMaterial)
        } else {
            EmptyView()
        }
    }
}

struct CrosswordGridView: View {
    var crossword: Crossword
    var boxWidth: CGFloat
    var getViewWidth: () -> CGFloat
    var synthesizer: AVSpeechSynthesizer

    @ObservedObject var userSettings: UserSettings

    @Binding var isErrorTrackingEnabled: Bool
    @Binding var focusedTag: Int
    @Binding var highlighted: [Int]
    @Binding var goingAcross: Bool
    @Binding var forceUpdate: Bool
    @Binding var becomeFirstResponder: Bool
    @Binding var isRebusMode: Bool

    var useSystemKeyboard: Bool = true
    var inputRelay: CrosswordInputRelay? = nil

    var body: some View {
        let rows: [Int] = Array(0...Int(self.crossword.height) - 1)
        let cols: [Int] = Array(0...Int(self.crossword.length) - 1)
        return VStack(spacing: 0) {
            ForEach(rows, id: \.self) { rowNum in
                HStack(spacing: 0) {
                    ForEach(cols, id: \.self) { colNum in
                        self.makeCellView(rowNum: rowNum, colNum: colNum)
                    }
                }
                .id("row" + String(rowNum))
            }
            if self.focusedTag != -1 {
                CrosswordTextFieldView(
                    crossword: self.crossword,
                    synthesizer: self.synthesizer, getViewWidth: self.getViewWidth,
                    userSettings: self.userSettings, focusedTag: self.$focusedTag,
                    isErrorTrackingEnabled: self.$isErrorTrackingEnabled,
                    highlighted: self.$highlighted, goingAcross: self.$goingAcross,
                    forceUpdate: self.$forceUpdate,
                    becomeFirstResponder: self.$becomeFirstResponder,
                    isRebusMode: self.$isRebusMode,
                    useSystemKeyboard: self.useSystemKeyboard,
                    inputRelay: self.inputRelay
                )
                .onKeyPress(phases: .down) { press in
                    return OnKeyPressUtils.onKeyPress(
                        press: press, focusedTag: self.$focusedTag,
                        crossword: self.crossword, userSettings: self.userSettings,
                        goingAcross: self.$goingAcross, isHighlighted: self.$highlighted)
                }
                .frame(width: 1, height: 1)
            }
        }
    }

    func makeCellView(rowNum: Int, colNum: Int) -> some View {
        let tag: Int = CrosswordUtils.getTagFromRowAndColNumbers(
            rowNum: rowNum, colNum: colNum,
            crossword: self.crossword)
        return CrosswordCellView(
            value: self.crossword.entry![tag],
            correctValue: self.crossword.solution?[safe: tag],
            receivedHelp: self.userSettings.showHelpIndicators
                ? self.crossword.helpTracking?[safe: tag] : false,
            symbol: self.crossword.symbols![tag],
            tag: tag,
            onTap: self.onTapCell,
            boxWidth: self.boxWidth,
            isErrorTrackingEnabled: self.isErrorTrackingEnabled,
            isFocused: self.focusedTag == tag,
            isHighlighted: self.highlighted.contains(tag),
        )
        .equatable()
        .frame(width: self.boxWidth, height: self.boxWidth).id("cell" + String(tag))
    }

    func onTapCell(tag: Int) {
        if self.crossword.entry![tag] == "." {
            return
        }

        if !self.becomeFirstResponder {
            self.becomeFirstResponder = true
        }

        if tag == self.focusedTag {
            ChangeFocusUtils.toggleDirection(
                focusedTag: tag, crossword: self.crossword,
                goingAcross: self.$goingAcross,
                isHighlighted: self.$highlighted)
        } else {
            self.isRebusMode = false
            ChangeFocusUtils.changeFocus(
                tag: tag, crossword: self.crossword,
                goingAcross: self.$goingAcross, focusedTag: self.$focusedTag,
                isHighlighted: self.$highlighted)
        }
    }
}

struct CrosswordFooter: View {
    var zoom: () -> Void
    var isZoomed: Bool
    var isPaused: Bool
    var pause: () -> Void
    var solveCell: (TimerWrapper) -> Void
    var isSolved: Bool
    var solvedTime: Int

    @EnvironmentObject var timerWrapper: TimerWrapper
    @Binding var isRebusMode: Bool
    @ObservedObject var userSettings: UserSettings

    var body: some View {
        HStack {
            Button(action: { self.zoom() }) {
                Image(
                    systemName: self.isZoomed
                        ? "minus.magnifyingglass"
                        : "plus.magnifyingglass"
                )
                .accessibilityLabel(self.isZoomed ? "Zoom out" : "Zoom in")
            }

            Button(action: { self.isRebusMode.toggle() }) {
                Image(systemName: self.isRebusMode ? "r.square.fill" : "r.square")
                    .accessibilityLabel(self.isRebusMode ? "Disable rebus mode" : "Enable rebus mode")
            }
            if self.userSettings.showTimer {
                Button(action: { self.pause() }) {
                    Image(systemName: "pause.fill")
                        .accessibilityLabel("Pause")
                }
            }
            if !self.userSettings.actionButtonsInToolbar {
                Button(action: { self.solveCell(self.timerWrapper) }) {
                    Image(systemName: "lifepreserver")
                        .accessibilityLabel("Solve Cell")
                }
            }
            Spacer()
            if self.userSettings.showTimer {
                TimerView(isSolved: self.isSolved, solvedTime: self.solvedTime, isPaused: self.isPaused)
            }
        }
    }

}
