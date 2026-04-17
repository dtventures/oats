import OatsCore
import SwiftUI

struct GuestAvatarsView: View {
    let attendees: [Attendee]
    var max: Int = 3

    private var visible: [Attendee] { Array(attendees.prefix(max)) }
    private var overflow: [Attendee] { Array(attendees.dropFirst(max)) }

    var body: some View {
        // Negative spacing produces correct layout width for overlapping circles
        HStack(spacing: -6) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { i, a in
                AvatarBubble(attendee: a, borderColor: .cream)
                    .zIndex(Double(visible.count - i))
            }
            if !overflow.isEmpty {
                OverflowBubble(attendees: overflow, borderColor: .cream)
                    .zIndex(0)
            }
        }
    }
}

// MARK: - Single avatar

struct AvatarBubble: View {
    let attendee: Attendee
    let borderColor: Color
    @State private var hovered = false

    var body: some View {
        ZStack {
            Circle()
                .fill(attendee.avatarColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(borderColor, lineWidth: 1.5))

            Text(attendee.initials)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(.white)
        }
        .onHover { hovered = $0 }
        .popover(isPresented: $hovered, arrowEdge: .bottom) {
            AvatarTooltip(name: attendee.name, email: attendee.email, color: attendee.avatarColor)
        }
    }
}

// MARK: - Overflow bubble

struct OverflowBubble: View {
    let attendees: [Attendee]
    let borderColor: Color
    @State private var hovered = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.checkboxBorder)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(borderColor, lineWidth: 1.5))

            Text("+\(attendees.count)")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
        }
        .onHover { hovered = $0 }
        .popover(isPresented: $hovered, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(attendees) { a in
                    Text(a.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color(red: 0.157, green: 0.149, blue: 0.122))
        }
    }
}

// MARK: - Tooltip popover content

struct AvatarTooltip: View {
    let name: String
    let email: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(
                    Text(Attendee(name: name, email: email).initials)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(email)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color(red: 0.157, green: 0.149, blue: 0.122))
    }
}
