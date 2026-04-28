import SwiftUI

/// 一个用于生成 Shot 应用图标的 SwiftUI 视图。
/// 遵循 macOS 11+ (Big Sur) 的 Squircle 设计规范。
struct AppIconView: View {
    var body: some View {
        ZStack {
            // 底层：带有深邃质感的背景
            RoundedRectangle(cornerRadius: 110, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 12)

            // 氛围感：底部的微弱彩色光晕
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 50)
                .offset(x: -50, y: 50)

            // 主体：玻璃质感选取框
            ZStack {
                // 彩虹渐变边缘 (模拟镜头折射)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            center: .center
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 220, height: 160)
                    .blur(radius: 0.5)

                // 玻璃层
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .frame(width: 220, height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )

                // 中心捕获点 (发光的蓝色)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .blue],
                            center: .center,
                            startRadius: 0,
                            endRadius: 10
                        )
                    )
                    .frame(width: 20, height: 20)
                    .shadow(color: .blue, radius: 10)
            }
            .rotationEffect(.degrees(-5))  // 稍微倾斜增加灵动感

            // 顶部强高光 (玻璃感)
            RoundedRectangle(cornerRadius: 110, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    ))
        }
        .frame(width: 512, height: 512)
        .padding(60)
    }
}

#Preview {
    AppIconView()
        .frame(width: 512, height: 512)
        .background(Color(white: 0.95))
}
