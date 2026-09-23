import SwiftUI

/// The Windows-style overlay: a translucent rounded panel containing a grid of
/// window previews, the selected one highlighted, with its title shown above.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    /// Called when the user clicks an item directly.
    var onPick: (Int) -> Void

    static let spacing: CGFloat = 12
    static let itemPadding: CGFloat = 8
    static let labelHeight: CGFloat = 14
    static let labelGap: CGFloat = 6

    /// Full size of one grid cell for a given thumbnail size.
    static func cellSize(for itemSize: CGSize) -> CGSize {
        CGSize(
            width: itemSize.width + itemPadding * 2,
            height: itemSize.height + labelGap + labelHeight + itemPadding * 2
        )
    }

    var body: some View {
        let cell = Self.cellSize(for: model.itemSize)
        let count = model.windows.count
        let columns = max(1, min(model.columns, count))
        let rows = max(1, (count + columns - 1) / columns)
        let visibleRows = min(rows, model.maxVisibleRows)
        let gridWidth = CGFloat(columns) * cell.width + CGFloat(columns - 1) * Self.spacing
        let gridHeight = CGFloat(visibleRows) * cell.height + CGFloat(visibleRows - 1) * Self.spacing

        VStack(spacing: 14) {
            Text(model.selectedWindow?.headerTitle ?? "")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: gridWidth)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cell.width), spacing: Self.spacing), count: columns),
                        spacing: Self.spacing
                    ) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                            ItemView(
                                window: window,
                                thumbnail: model.thumbnails[window.id],
                                size: model.itemSize,
                                isSelected: index == model.selected
                            )
                            .id(window.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(index) }
                            .onContinuousHover { phase in
                                if case .active = phase { model.hover(index) }
                            }
                        }
                    }
                }
                .frame(width: gridWidth, height: gridHeight)
                .onChange(of: model.selected) { _, newValue in
                    guard model.windows.indices.contains(newValue) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(model.windows[newValue].id, anchor: .center)
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(
                    VisualEffectBlur()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }
}

private struct ItemView: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let size: CGSize
    let isSelected: Bool

    var body: some View {
        VStack(spacing: SwitcherView.labelGap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                        // Dim previews of windows that aren't currently visible.
                        .opacity(window.isOffscreen ? 0.55 : 1)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                }

                // App icon badge in the corner for context.
                if thumbnail != nil, let icon = window.appIcon {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                                .padding(5)
                        }
                    }
                }

                if let badge = stateBadge {
                    VStack {
                        HStack {
                            Image(systemName: badge.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Circle().fill(.black.opacity(0.6)))
                                .help(badge.label)
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size.width, height: size.height)

            Text(window.displayTitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size.width, height: SwitcherView.labelHeight)
        }
        .padding(SwitcherView.itemPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.9) : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.headerTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var stateBadge: (symbol: String, label: String)? {
        if window.isMinimized { return ("minus", "Minimized") }
        if window.isAppHidden { return ("eye.slash", "Hidden") }
        if window.isOnOtherSpace { return ("rectangle.on.rectangle", "On another Space") }
        return nil
    }
}

/// Bridges NSVisualEffectView for a frosted-glass background.
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
