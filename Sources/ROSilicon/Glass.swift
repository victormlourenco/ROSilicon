import SwiftUI

/// Liquid Glass, and somewhere for it to sit.
///
/// The effect itself is macOS 26. The app still runs on macOS 14, so every
/// piece here has a second form — a frosted material card, which is as close as
/// those releases get. This file is the only place that chooses between them:
/// the views ask for `glassCard()` and never learn which one they got.

// MARK: - Backdrop

/// Glass refracts whatever is behind it, so a flat window background renders it
/// all but invisible. This is that something: the window's own colour, washed
/// with two soft blooms the cards above then pick up and bend.
///
/// Both blooms are kept faint. They have to read through `.background` in light
/// mode without turning the window into a poster, and the glass amplifies them
/// where the cards overlap.
struct GlassBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay(alignment: .topLeading) {
                bloom(.accentColor, opacity: 0.30, offset: -170)
            }
            .overlay(alignment: .bottomTrailing) {
                bloom(.indigo, opacity: 0.24, offset: 170)
            }
            .overlay(alignment: .topLeading) { windowButtons }
            .ignoresSafeArea()
    }

    /// A pill of glass beneath the close, minimise and zoom buttons.
    ///
    /// Those are AppKit's own and cannot be restyled, but with the title bar
    /// hidden they sit directly on the backdrop with nothing under them. They
    /// draw above anything the view puts up, so laying this where they are
    /// gives them the same footing as every other control in the window. The
    /// size is measured from them: they run from 10 to 61 across and 8 to 20
    /// down, and this leaves four points around that.
    private var windowButtons: some View {
        Color.clear
            .frame(width: 59, height: 20)
            .modifier(GlassSurface(shape: Capsule(style: .continuous)))
            .padding(.leading, 6)
            .padding(.top, 4)
            .allowsHitTesting(false)
    }

    /// A circle of colour fading to nothing, pulled out past the corner it is
    /// aligned to so that only its falloff lands in the window and no seam shows
    /// where it ends.
    private func bloom(_ colour: Color, opacity: Double, offset: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [colour.opacity(opacity), colour.opacity(0)],
                    center: .center, startRadius: 0, endRadius: 320)
            )
            .frame(width: 640, height: 640)
            .offset(x: offset, y: offset)
            .blur(radius: 40)
            .allowsHitTesting(false)
    }
}

// MARK: - Cards

extension View {
    /// The pane shape the window is built from: content lifted off the backdrop
    /// on a sheet of glass.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Bordered on macOS 14 and 15, glass on 26.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// The one call to action in the window: Play.
    ///
    /// Not `.glassProminent`, which fills the capsule with the accent colour
    /// until nothing shows through — beside the glass around it, it reads as a
    /// painted button rather than a lit one. Tinting regular glass keeps the
    /// backdrop visible through it and still leaves no doubt which button is
    /// the one to press.
    @ViewBuilder
    func glassActionButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(TintedGlassButtonStyle())
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// A menu as a button rather than as a bare label. The label form has no
    /// button behind it, so nothing answers the pointer: no hover, no press.
    /// This gives the menus the same glass — and the same reactions — as the
    /// buttons below them.
    @ViewBuilder
    func glassMenuButton() -> some View {
        if #available(macOS 26, *) {
            menuStyle(.button).buttonStyle(.glass)
        } else {
            menuStyle(.button).buttonStyle(.bordered)
        }
    }
}

/// Regular glass under the accent colour, mixed thinly enough to stay glass.
///
/// A style rather than a `glassEffect` at the call site because the button
/// spends most of its life disabled — there is nothing to play until the game
/// is installed — and only a view can read `isEnabled`.
@available(macOS 26, *)
private struct TintedGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    /// Glass has an `interactive()` mode that lights and springs under a
    /// press, and it is no use here: it answers presses that land on the glass
    /// itself, and inside a button style the button has already taken them. So
    /// the motion is driven from the state the style is given instead — the
    /// press from the configuration, the pointer from `onHover`, since a style
    /// is told about one and not the other.
    private struct Surface: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.body.weight(.medium))
                // Tuned to stand the same height as a large `.glass` button,
                // which is what Install and Cancel beside it are.
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(tint), in: Capsule(style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.spring(response: 0.22, dampingFraction: 0.6),
                           value: configuration.isPressed)
        }

        /// Deeper under the pointer, deeper again under a press, and gone when
        /// there is nothing to play.
        private var tint: Color {
            guard isEnabled else { return .accentColor.opacity(0) }
            if configuration.isPressed { return .accentColor.opacity(0.70) }
            return .accentColor.opacity(hovering ? 0.58 : 0.45)
        }
    }
}

/// The single availability check. On macOS 26 this is real glass, which brings
/// its own edge treatment and shadow; before that it is a material with both of
/// those drawn by hand — a hairline border so the card has an edge against a
/// pale backdrop, and a shadow so it still reads as floating.
private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}

// MARK: - Grouping

/// Glass that shares a container flows together as it moves — neighbouring
/// pieces merge rather than crossing over one another. Before macOS 26 there is
/// nothing to coordinate, so this is the views themselves and costs nothing.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
