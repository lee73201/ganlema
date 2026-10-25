import AppKit
import SwiftUI
import FocusDockCore

struct AppearanceSettingsView: View {
    @ObservedObject var controller: PanelWindowController
    private var settings: Binding<FloatingAppearance> { $controller.floatingAppearance }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("悬浮外观").font(.system(size: 21, weight: .semibold))
                    Text("实时应用到桌面胶囊 · 自动保存").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("恢复默认") { controller.floatingAppearance = FloatingAppearance() }
            }.padding(22)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 6) {
                        ForEach(CapsuleShape.allCases) { shape in
                            Button { settings.wrappedValue.shape = shape } label: {
                                VStack(spacing: 9) {
                                    let sample = sampleAppearance(shape)
                                    RoundedRectangle(cornerRadius: sample.radius(in: CGSize(width: shape == .circle ? 28 : 56, height: shape == .strip ? 10 : 28)))
                                        .fill(shape == .island ? Color.primary.opacity(0.85) : controller.floatingAppearance.accentColor.opacity(0.35))
                                        .frame(width: shape == .circle ? 28 : 56, height: shape == .strip ? 10 : 28).frame(height: 30)
                                    Text(shape.title).font(.system(size: 10)).lineLimit(1)
                                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(controller.floatingAppearance.shape == shape ? controller.floatingAppearance.accentColor.opacity(0.16) : .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(controller.floatingAppearance.shape == shape ? controller.floatingAppearance.accentColor.opacity(0.6) : .clear))
                            }.buttonStyle(.plain).accessibilityLabel(shape.title).accessibilityAddTraits(controller.floatingAppearance.shape == shape ? .isSelected : [])
                        }
                    }
                    VStack(spacing: 9) {
                        let value = controller.floatingAppearance
                        let size = value.size(urgency: controller.urgency)
                        CapsuleAppearanceView(appearance: value, count: controller.repository.items.filter { !$0.isCompleted }.count, deadline: controller.nearestDeadlineTitle, urgent: controller.urgency != .normal)
                            .frame(width: size.width, height: size.height)
                            .background(PreviewGlass(appearance: value).overlay(value.shape == .island ? Color.black.opacity(0.7 + value.opacity * 0.2) : .clear)).clipShape(RoundedRectangle(cornerRadius: value.radius(in: size)))
                            .shadow(color: .black.opacity(value.shadow == .off ? 0 : value.shadow == .subtle ? 0.08 : 0.22), radius: value.shadow == .subtle ? 3 : 8, y: 3)
                            .frame(height: 90)
                        Text("实时预览 · \(Int(size.width)) × \(Int(size.height)) pt").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                    section("外观") {
                        row("尺寸") { Picker("尺寸", selection: settings.scale) { ForEach(CapsuleScale.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                        row("毛玻璃材质") { Picker("毛玻璃材质", selection: settings.material) { ForEach(CapsuleMaterial.allCases, id: \.self) { Text($0.title).tag($0) } } }
                        row("颜色") { Picker("颜色", selection: settings.colorMode) { ForEach(CapsuleColorMode.allCases, id: \.self) { Text($0.title).tag($0) } } }
                        if controller.floatingAppearance.colorMode == .custom {
                            ColorPicker("强调色", selection: Binding(get: { controller.floatingAppearance.accentColor }, set: { color in
                                if let rgb = NSColor(color).usingColorSpace(.deviceRGB) { var value = controller.floatingAppearance; value.red = rgb.redComponent; value.green = rgb.greenComponent; value.blue = rgb.blueComponent; controller.floatingAppearance = value }
                            }), supportsOpacity: false)
                        }
                        slider("背景不透明度", value: settings.opacity, range: 0.15...1, text: "\(Int(controller.floatingAppearance.opacity * 100))%")
                        if controller.floatingAppearance.shape == .rectangle { slider("圆角", value: settings.cornerRadius, range: 4...24, text: "\(Int(controller.floatingAppearance.cornerRadius)) pt") }
                        row("阴影") { Picker("阴影", selection: settings.shadow) { ForEach(CapsuleShadow.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                        row("显示内容") { Picker("显示内容", selection: settings.content) { ForEach(CapsuleContent.allCases, id: \.self) { Text($0.title).tag($0) } } }
                        Text("圆形以图标或数量显示；细条使用紧凑入口。展开面板保留独立尺寸与原生毛玻璃。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    section("交互") {
                        slider("悬停展开", value: settings.hoverDelay, range: 0.1...1.5, text: "\(Int(controller.floatingAppearance.hoverDelay * 1000)) ms")
                        slider("离开收起", value: settings.collapseDelay, range: 0.15...3, text: "\(Int(controller.floatingAppearance.collapseDelay * 1000)) ms")
                        Toggle("点击胶囊固定展开", isOn: settings.clickToPin)
                        Toggle("拖动后吸附屏幕边缘", isOn: settings.edgeSnap)
                        Text("自动向屏幕空余较多的一侧展开；按显示器分别记住位置和展开尺寸。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 24)
            }.scrollBounceBehavior(.basedOnSize)
        }.frame(minWidth: 480, minHeight: 580).tint(controller.floatingAppearance.accentColor)
    }
    private func sampleAppearance(_ shape: CapsuleShape) -> FloatingAppearance { var value = controller.floatingAppearance; value.shape = shape; return value }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { Text(title).font(.system(size: 12, weight: .semibold)); content() }.font(.system(size: 12))
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).frame(width: 100, alignment: .leading); content().labelsHidden().frame(maxWidth: .infinity) }
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        HStack { Text(title).frame(width: 100, alignment: .leading); Slider(value: value, in: range); Text(text).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .trailing) }
    }
}

private struct PreviewGlass: NSViewRepresentable {
    let appearance: FloatingAppearance
    func makeNSView(context: Context) -> NSVisualEffectView { let view = NSVisualEffectView(); view.blendingMode = .behindWindow; view.state = .active; return view }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = appearance.material == .menu ? .menu : appearance.material == .hud ? .hudWindow : .popover
        view.appearance = appearance.shape == .island ? NSAppearance(named: .darkAqua) : appearance.appAppearance
        view.alphaValue = appearance.opacity
    }
}
