import AppKit
import SwiftUI

struct CocoSpeech {
    let text: String
    var detail: String?
    var detailIcon: String?
    var join: URL?
    var joinLabel: String?
    var lifetime: TimeInterval = 24
}

enum BubblePointer {
    case left, right, top, bottom
}

struct BubblePlacement {
    let frame: CGRect
    let pointer: BubblePointer
    let fraction: CGFloat

    static func beside(window: CGRect, avatar: CGPoint, size: CGSize, on display: CGRect) -> Self {
        let gap: CGFloat = 3
        let left = window.minX - display.minX - gap
        let right = display.maxX - window.maxX - gap
        let above = display.maxY - window.maxY - gap
        let below = window.minY - display.minY - gap
        let pointer: BubblePointer
        let origin: CGPoint
        if max(left, right) >= size.width || max(above, below) < size.height {
            if right >= left {
                pointer = .left
                origin = CGPoint(x: window.maxX + gap, y: avatar.y - size.height / 2)
            } else {
                pointer = .right
                origin = CGPoint(x: window.minX - size.width - gap, y: avatar.y - size.height / 2)
            }
        } else if above >= below {
            pointer = .bottom
            origin = CGPoint(x: avatar.x - size.width / 2, y: window.maxY + gap)
        } else {
            pointer = .top
            origin = CGPoint(x: avatar.x - size.width / 2, y: window.minY - size.height - gap)
        }
        let frame = CGRect(x: min(max(origin.x, display.minX), max(display.minX, display.maxX - size.width)),
                           y: min(max(origin.y, display.minY), max(display.minY, display.maxY - size.height)),
                           width: size.width, height: size.height)
        let horizontal = pointer == .top || pointer == .bottom
        let relative = horizontal ? (avatar.x - frame.minX) / size.width : 1 - (avatar.y - frame.minY) / size.height
        return BubblePlacement(frame: frame, pointer: pointer, fraction: min(max(relative, 0.19), 0.81))
    }
}

private struct BubbleOutline: Shape {
    let pointer: BubblePointer
    let fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0.5)
        let tip: CGFloat = 11
        let half: CGFloat = 7
        var body = rect
        switch pointer {
        case .left:
            body.origin.x += tip
            body.size.width -= tip
        case .right: body.size.width -= tip
        case .top:
            body.origin.y += tip
            body.size.height -= tip
        case .bottom: body.size.height -= tip
        }
        let r = min(19, body.width / 2, body.height / 2)
        let x = min(max(rect.minX + rect.width * fraction, body.minX + r + half), body.maxX - r - half)
        let y = min(max(rect.minY + rect.height * fraction, body.minY + r + half), body.maxY - r - half)
        var outline = Path()
        outline.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if pointer == .top {
            outline.addLine(to: CGPoint(x: x - half, y: body.minY))
            outline.addLine(to: CGPoint(x: x, y: rect.minY))
            outline.addLine(to: CGPoint(x: x + half, y: body.minY))
        }
        outline.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        outline.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + r), control: CGPoint(x: body.maxX, y: body.minY))
        if pointer == .right {
            outline.addLine(to: CGPoint(x: body.maxX, y: y - half))
            outline.addLine(to: CGPoint(x: rect.maxX, y: y))
            outline.addLine(to: CGPoint(x: body.maxX, y: y + half))
        }
        outline.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        outline.addQuadCurve(to: CGPoint(x: body.maxX - r, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        if pointer == .bottom {
            outline.addLine(to: CGPoint(x: x + half, y: body.maxY))
            outline.addLine(to: CGPoint(x: x, y: rect.maxY))
            outline.addLine(to: CGPoint(x: x - half, y: body.maxY))
        }
        outline.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        outline.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - r), control: CGPoint(x: body.minX, y: body.maxY))
        if pointer == .left {
            outline.addLine(to: CGPoint(x: body.minX, y: y + half))
            outline.addLine(to: CGPoint(x: rect.minX, y: y))
            outline.addLine(to: CGPoint(x: body.minX, y: y - half))
        }
        outline.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        outline.addQuadCurve(to: CGPoint(x: body.minX + r, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        outline.closeSubpath()
        return outline
    }
}

struct CocoSpeechView: View {
    let speech: CocoSpeech
    let pointer: BubblePointer
    let fraction: CGFloat
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var background: LinearGradient {
        let colors = scheme == .dark
            ? [Color(red: 0.15, green: 0.20, blue: 0.30), Color(red: 0.09, green: 0.14, blue: 0.23)]
            : [.white, Color(red: 0.92, green: 0.96, blue: 1)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(speech.text)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = speech.detail {
                        HStack(alignment: .top, spacing: 5) {
                            if let icon = speech.detailIcon {
                                Image(systemName: icon).accessibilityHidden(true)
                            }
                            Text(detail).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background(.primary.opacity(0.07), in: Circle())
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss reminder")
            }
            if let link = speech.join, let label = speech.joinLabel {
                Button {
                    NSWorkspace.shared.open(link)
                    dismiss()
                } label: {
                    Label(label, systemImage: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 9)
                        .background(Color(red: 0.17, green: 0.40, blue: 0.78).gradient,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .padding(.leading, pointer == .left ? 11 : 0)
        .padding(.trailing, pointer == .right ? 11 : 0)
        .padding(.top, pointer == .top ? 11 : 0)
        .padding(.bottom, pointer == .bottom ? 11 : 0)
        .background {
            let shape = BubbleOutline(pointer: pointer, fraction: fraction)
            shape.fill(background)
                .overlay(shape.stroke(.blue.opacity(scheme == .dark ? 0.30 : 0.21), lineWidth: 1))
                .shadow(color: .black.opacity(0.24), radius: 7, y: 3)
        }
        .padding(8)
        .frame(width: 302)
    }
}

final class CocoSpeechHost: NSHostingView<CocoSpeechView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
