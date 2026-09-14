//
//  ModeToggle.swift
//  ThatWay
//
//  Floating draggable Point/Guidance switch that also carries the theme toggle,
//  and steers clear of the dial as it's dragged.
//

import SwiftUI

struct ModeToggle: View {
    @EnvironmentObject var app: AppModel
    let k: CGFloat
    let dialCenter: CGPoint
    let bounds: CGSize

    @GestureState private var dragOffset: CGSize = .zero
    @State private var dragStart: CGPoint?

    var body: some View {
        let theme = app.currentTheme

        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 6) {
                Text("Point")
                    .font(.nunito(11, .extraBold))
                    .foregroundStyle(theme.ink)
                    .opacity(app.guiding ? 0.3 : 1)
                Text("Guidance")
                    .font(.nunito(11, .extraBold))
                    .foregroundStyle(theme.ink)
                    .opacity(app.guiding ? 1 : 0.3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .trailing)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.ink.opacity(0.14))
                    .frame(width: 22, height: 44)
                Circle()
                    .fill(app.accent)
                    .frame(width: 16, height: 16)
                    .shadow(color: app.accent, radius: 7)
                    .offset(y: app.guiding ? 22 : 3)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: app.guiding)
            }
        }
        .padding(.horizontal, 11)
        .frame(width: AppModel.togW, height: AppModel.togH)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink.opacity(0.16)))
        .shadow(color: .black.opacity(app.dragging ? 0.5 : 0.32), radius: app.dragging ? 22 : 12, y: app.dragging ? 12 : 8)
        .overlay(alignment: .topLeading) {
            Button {
                app.toggleTheme()
            } label: {
                Circle()
                    .fill(theme.screen)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(theme.ink.opacity(0.2)))
                    .overlay(
                        Circle()
                            .fill(theme.light ? Color(hex: "FFD86B") : theme.ink.opacity(0.22))
                            .frame(width: 14, height: 14)
                            .shadow(color: theme.light ? Color(hex: "FFD86B").opacity(0.9) : .clear, radius: 8)
                    )
            }
            .offset(x: -13, y: -15)
        }
        .position(x: app.togX + AppModel.togW / 2 + dragOffset.width, y: app.togY + AppModel.togH / 2 + dragOffset.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onChanged { value in
                    if !app.dragging, value.translation.width * value.translation.width + value.translation.height * value.translation.height > 25 {
                        app.dragging = true
                    }
                }
                .onEnded { value in
                    let moved = value.translation.width * value.translation.width + value.translation.height * value.translation.height > 25
                    if moved {
                        let p = app.placeToggle(app.togX + value.translation.width, app.togY + value.translation.height, in: bounds, dialCenter: dialCenter)
                        app.togX = p.x
                        app.togY = p.y
                    } else {
                        app.flipMode()
                    }
                    app.dragging = false
                }
        )
        .animation(app.dragging ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: app.togX)
        .animation(app.dragging ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: app.togY)
    }
}
