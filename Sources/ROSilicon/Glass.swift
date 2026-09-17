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
            .ignoresSafeArea()
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

    /// The same sheet drawn as a pill, for the small floating controls in the
    /// header rather than a full-width pane.
    func glassPill() -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous)))
    }

    /// Bordered on macOS 14 and 15, glass on 26. Prominent is the one call to
    /// action in the window — Play.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
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
