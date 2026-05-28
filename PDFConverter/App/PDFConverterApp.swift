import SwiftUI
import PDFConverterCore

/// `@main` 标记这是 SwiftUI App 的入口点。
/// 当一个 SwiftUI 项目中只有一个结构体标记了 `@main` 时，系统会从这个结构体启动整个应用。
/// 它的作用类似于传统 iOS/macOS 开发中的 `main.swift` 或 `AppDelegate`，但更加声明式。
@main
struct PDFConverterApp: App {
    /// `@StateObject` 创建并持有一个 ViewModel 实例。
    /// 与 `@ObservedObject` 不同，`@StateObject` 是数据的「拥有者」——它的生命周期与 App 一致，
    /// 不会因为视图重建而被重新创建。这里创建的 `AppViewModel` 是整个应用的唯一数据源。
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                /// `.environmentObject(viewModel)` 将 ViewModel 注入到整个视图层级中。
                /// 任何子视图都可以通过 `@EnvironmentObject private var viewModel: AppViewModel`
                /// 来获取这个共享实例，无需逐层手动传递。这是 SwiftUI 中跨视图共享数据的标准方式。
                .environmentObject(viewModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        /// `.commands` 修饰符用于自定义 macOS 菜单栏。
        /// 这里替换了默认的「新建」菜单项，改为「打开文件…」，快捷键为 `Cmd+O`。
        /// `CommandGroup(replacing: .newItem)` 表示用我们定义的按钮覆盖系统默认的 New 菜单项。
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…") { viewModel.pickFiles() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        /// `Settings` 场景是 macOS 专用的偏好设置窗口。
        /// 当用户点击菜单栏的「PDF Converter → 设置…」（或按 `Cmd+,`）时，
        /// 系统会打开这个窗口并显示 `SettingsView`。
        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}