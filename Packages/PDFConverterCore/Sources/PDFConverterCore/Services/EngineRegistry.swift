import Foundation

/// 引擎注册中心，持有所有 ``ConversionEngine`` 实例，维护 `ConversionType → Engine` 的映射表。
///
/// 注册中心是整个转换系统的"调度中枢"——当 ``JobOrchestrator`` 需要执行一个任务时，
/// 它通过 `engine(for:)` 方法查找对应该转换类型的引擎，然后将任务分派给它。
///
/// 设计要点：
/// - **单例模式**：通过 `shared` 提供全局唯一实例，避免多次初始化引擎
/// - **预计算索引**：初始化时遍历所有引擎的 `supportedTypes()`，构建类型到引擎的反向映射表，
///   后续查找是 O(1) 的哈希表查询
/// - **依赖注入**：`init` 支持注入自定义引擎列表，方便单元测试时使用 Mock 引擎
///
/// ## 如何添加新引擎
/// 1. 创建实现了 ``ConversionEngine`` 的结构体
/// 2. 在 `init` 的 `list` 默认值中加入该引擎实例
/// 3. 注册中心会自动扫描 `supportedTypes()` 并更新映射表
public final class EngineRegistry: @unchecked Sendable {
    /// 全局共享实例，使用默认的本地引擎列表
    public static let shared = EngineRegistry()

    /// 所有已注册的引擎实例
    private let engines: [any ConversionEngine]
    /// `ConversionType → Engine` 的快速查找表，在初始化时预计算
    private let typeIndex: [ConversionType: any ConversionEngine]

    /// 初始化引擎注册中心。
    ///
    /// - Parameter engines: 自定义的引擎列表。如果不传参，则使用包含所有本地引擎的默认列表。
    ///   这个参数主要用于单元测试——可以传入 Mock 引擎来模拟各种转换场景。
    public init(engines: [any ConversionEngine]? = nil) {
        let list = engines ?? [
            PDFKitEngine(),
            PopplerEngine(),
            QpdfEngine(),
            GhostscriptEngine(),
            OfficeAutomationEngine(),
            TesseractEngine()
        ]
        self.engines = list

        // 构建类型到引擎的反向索引：
        // 遍历每个引擎 → 遍历引擎支持的所有类型 → 建立映射关系
        var index: [ConversionType: any ConversionEngine] = [:]
        for engine in list {
            for type in engine.supportedTypes() {
                index[type] = engine
            }
        }
        self.typeIndex = index
    }

    /// 根据转换类型查找对应的引擎。
    ///
    /// - Parameter type: 要执行的转换类型（如 `.pdfToPNG`、`.mergePDF`）
    /// - Returns: 对应的引擎实例，如果没有引擎支持该类型则返回 `nil`
    ///
    /// ## 查找过程
    /// 这是一个 O(1) 的字典查询——因为映射表在 `init` 时已经预计算好了，
    /// 所以运行时查找非常快，不会成为性能瓶颈。
    public func engine(for type: ConversionType) -> (any ConversionEngine)? {
        typeIndex[type]
    }

    /// 返回所有已注册的引擎列表。
    public func allEngines() -> [any ConversionEngine] {
        engines
    }

    /// 根据引擎种类反向查找该引擎支持的所有转换类型。
    ///
    /// 这是一个反向查询：已知引擎种类，想知道它能处理哪些操作。
    /// 主要用于设置页面——展示每个引擎的工具可用性和支持的功能列表。
    ///
    /// - Parameter kind: 引擎种类标识（如 `.poppler`、`.qpdf`）
    /// - Returns: 该引擎支持的所有转换类型，按显示名称字典序排列
    ///
    /// 示例：传入 `.qpdf` 会返回 `[.decryptPDF, .encryptPDF, .splitPDF]`
    public func types(for kind: EngineKind) -> [ConversionType] {
        engines
            .filter { $0.kind == kind }
            .flatMap { Array($0.supportedTypes()) }
            .sorted { $0.displayName < $1.displayName }
    }
}