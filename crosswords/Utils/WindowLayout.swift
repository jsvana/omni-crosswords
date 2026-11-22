//
//  WindowLayout.swift
//  crosswords
//
//  Layout decisions are driven by the size of the window the app is drawn in,
//  not by the device or its screen. A foldable phone changes that size while
//  the app is running, so nothing here may be read once and kept.
//

import SwiftUI

enum CrosswordLayoutMode: Equatable {
    /// The original layout: grid on top, system keyboard with the clue toolbar.
    case standard
    /// A short, narrow window (a closed iPhone Duo, the smallest phones).
    /// The whole grid sits above a built-in keyboard that is much shorter than the system one.
    case compact
    /// A short, wide window (an open iPhone Duo, a small iPad in landscape).
    /// The grid fills the height on the leading side; clues and a built-in keyboard sit beside it.
    case wide

    static func forWindow(_ size: CGSize) -> CrosswordLayoutMode {
        #if DEBUG
            // `-layout compact` (or wide, standard) forces a layout whatever the window size
            switch UserDefaults.standard.string(forKey: "layout") {
            case "standard": return .standard
            case "compact": return .compact
            case "wide": return .wide
            default: break
            }
        #endif
        if ProcessInfo.processInfo.isiOSAppOnMac || size.width <= 0 || size.height <= 0 {
            return .standard
        }
        if size.width >= Constants.wideLayoutMinWidth && size.width > size.height
            && size.height < Constants.wideLayoutMaxHeight
        {
            return .wide
        }
        if size.width < Constants.wideLayoutMinWidth && size.height < Constants.compactLayoutMaxHeight {
            return .compact
        }
        return .standard
    }

    var usesSystemKeyboard: Bool {
        return self == .standard
    }
}

private struct WindowSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// Size of the window, including the areas under the status bar and the keyboard.
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

/// Holds the window size as UIKit reports it. SwiftUI geometry is not used for this
/// because it shrinks while the keyboard is up, and the layout must not follow the keyboard.
final class WindowSizeModel: ObservableObject {
    @Published var size: CGSize

    init(size: CGSize) {
        self.size = size
    }
}

/// Root hosting controller that keeps a `WindowSizeModel` in step with its view,
/// which fills the window and is resized with it.
final class WindowSizeHostingController<Content: View>: UIHostingController<WindowSizeProvider<Content>> {
    private let model: WindowSizeModel

    init(initialSize: CGSize, @ViewBuilder content: () -> Content) {
        let model = WindowSizeModel(size: initialSize)
        self.model = model
        super.init(rootView: WindowSizeProvider(model: model, content: content))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let newSize = self.view.bounds.size
        if newSize != self.model.size {
            self.model.size = newSize
        }
    }
}

/// Publishes the live window size to its content through `\.windowSize`.
struct WindowSizeProvider<Content: View>: View {
    @ObservedObject private var model: WindowSizeModel
    private let content: Content

    init(model: WindowSizeModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        self.framedContent
            .environment(\.windowSize, WindowSizeProvider.debugCanvas ?? self.model.size)
    }

    @ViewBuilder
    private var framedContent: some View {
        if let canvas = WindowSizeProvider.debugCanvas {
            self.content
                .frame(width: canvas.width, height: canvas.height)
                .clipped()
        } else {
            self.content
        }
    }

    /// Debug builds accept `-canvas 951x669` to draw the app at a fixed size,
    /// which stands in for devices the simulator cannot run.
    private static var debugCanvas: CGSize? {
        #if DEBUG
            guard let value = UserDefaults.standard.string(forKey: "canvas") else {
                return nil
            }
            let parts = value.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 && parts[0] > 0 && parts[1] > 0 {
                return CGSize(width: parts[0], height: parts[1])
            }
        #endif
        return nil
    }
}
