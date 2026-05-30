import SwiftUI

/// The Windows-style overlay: a translucent rounded panel containing a row of
/// window previews, the selected one highlighted, with its title shown above.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    /// Called when the user clicks an item directly.
    var onPick: (Int) -> Void

    private let itemSize = CGSize(width: 200, height: 130)
    private let spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: 14) {
            Text(model.selectedWindow?.displayTitle ?? "")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 760)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                            ItemView(
                                window: window,
                                size: itemSize,
                                isSelected: index == model.selected
                            )
                            .id(index)
                            .onTapGesture { onPick(index) }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: 5 * (itemSize.width + spacing))
                .onChange(of: model.selected) { _, newValue in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
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
    let size: CGSize
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))

                if let thumb = window.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                }

                // App icon badge in the corner for context.
                if window.thumbnail != nil, let icon = window.appIcon {
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
            }
            .frame(width: size.width, height: size.height)

            Text(window.displayTitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size.width)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.9) : .clear, lineWidth: 2)
        )
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
