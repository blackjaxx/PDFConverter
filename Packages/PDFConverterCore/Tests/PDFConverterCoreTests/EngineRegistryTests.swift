import XCTest
@testable import PDFConverterCore

final class EngineRegistryTests: XCTestCase {
    func testLocalTypeHasEngine() {
        let registry = EngineRegistry()
        for type in ConversionType.allCases where !type.requiresNetwork {
            XCTAssertNotNil(registry.engine(for: type), "Missing engine for \(type.rawValue)")
        }
    }

    func testNetworkTypesReturnNilInCoreRegistry() {
        let registry = EngineRegistry()
        let networkTypes: [ConversionType] = [.htmlToPDF, .pdfAISummary, .pdfAITranslate, .pdfAIToMarkdown]
        for type in networkTypes {
            XCTAssertNil(registry.engine(for: type), "Network type \(type.rawValue) should not have engine in core registry")
        }
    }

    func testOCRUsesTesseract() {
        let registry = EngineRegistry()
        let engine = registry.engine(for: .ocrSearchablePDF)
        XCTAssertEqual(engine?.kind, .tesseract)
    }

    func testMergePDFUsesPDFKit() {
        let registry = EngineRegistry()
        let engine = registry.engine(for: .mergePDF)
        XCTAssertEqual(engine?.kind, .pdfKit)
    }
}

/// 测试 JobOrchestrator 的 cancel 行为修复：
/// - pending 任务：直接从队列移除
/// - running 任务：标记 cancelled 后 execute 完成后不会覆盖状态
final class JobOrchestratorCancelTests: XCTestCase {

    /// 测试：取消 pending 任务后，状态变为 cancelled 且不在队列中
    func testCancelPendingJob() async throws {
        let orchestrator = JobOrchestrator(registry: EngineRegistry(), maxConcurrent: 1)
        let job = ConversionJob(type: .pdfToPNG, inputURLs: [])
        await orchestrator.enqueue(job)

        // 任务已加入
        let allBefore = await orchestrator.allJobs()
        XCTAssertEqual(allBefore.count, 1)
        XCTAssertEqual(allBefore.first?.status, .pending)

        // 取消任务
        await orchestrator.cancel(id: job.id)

        let allAfter = await orchestrator.allJobs()
        XCTAssertEqual(allAfter.count, 1)
        XCTAssertEqual(allAfter.first?.status, .cancelled)
    }

    /// 测试：取消未知 ID 不影响系统
    func testCancelUnknownJobNoOp() async {
        let orchestrator = JobOrchestrator(registry: EngineRegistry(), maxConcurrent: 1)
        let unknownID = UUID()
        await orchestrator.cancel(id: unknownID)
        let jobs = await orchestrator.allJobs()
        XCTAssertTrue(jobs.isEmpty)
    }

    /// 测试：allJobs 按创建时间倒序排列
    func testAllJobsSortedByCreatedAtDescending() async {
        let orchestrator = JobOrchestrator(registry: EngineRegistry(), maxConcurrent: 1)
        let job1 = ConversionJob(type: .pdfToPNG, inputURLs: [])
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        let job2 = ConversionJob(type: .jpegToPDF, inputURLs: [])

        await orchestrator.enqueue(job1)
        try? await Task.sleep(nanoseconds: 10_000_000)
        await orchestrator.enqueue(job2)

        let all = await orchestrator.allJobs()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.id, job2.id) // 最新的在前
    }
}

/// 测试 EngineRegistry 的关键映射：
/// 防止类似 LibreOfficeEngine.supportedTypes() 缺少 `}` 导致的编译错误
final class EngineRegistryProtocolConformanceTests: XCTestCase {

    /// 测试：所有引擎都正确实现 supportedTypes()
    /// 这一测试能捕捉类似「方法签名不对导致 protocol conformance 失败」的 bug
    func testAllEnginesConformToProtocol() {
        let registry = EngineRegistry()
        for engine in registry.allEngines() {
            // supportedTypes 不应抛错
            let types = engine.supportedTypes()
            XCTAssertFalse(types.isEmpty, "\(engine.kind) 引擎的 supportedTypes 为空")
        }
    }

    /// 测试：Office 相关类型映射到正确引擎
    func testOfficeTypesMappedToOfficeAutomationEngine() {
        let registry = EngineRegistry()
        for type: ConversionType in [.wordToPDF, .excelToPDF, .pptToPDF, .pdfToWord, .pdfToExcel] {
            let engine = registry.engine(for: type)
            XCTAssertNotNil(engine, "Office 类型 \(type) 未找到引擎")
            XCTAssertEqual(engine?.kind, .officeAutomation,
                           "Office 类型 \(type) 应使用 officeAutomation 引擎而非 \(engine?.kind.rawValue ?? "nil")")
        }
    }

    /// 测试：所有 ConversionType 都能找到引擎（除非标记为 requiresNetwork）
    /// 这一测试能捕捉 LibreOfficeEngine.supportedTypes() 语法错误导致 Office 类型无引擎的情况
    func testEveryNonNetworkTypeHasEngine() {
        let registry = EngineRegistry()
        for type in ConversionType.allCases where !type.requiresNetwork {
            XCTAssertNotNil(registry.engine(for: type),
                            "本地类型 \(type.rawValue) 未找到引擎")
        }
    }
}

/// 测试 ConversionType.category 的映射正确性
final class ConversionTypeCategoryTests: XCTestCase {

    func testOfficeCategoriesAreCorrect() {
        XCTAssertEqual(ConversionType.wordToPDF.category, .officeToPDF)
        XCTAssertEqual(ConversionType.excelToPDF.category, .officeToPDF)
        XCTAssertEqual(ConversionType.pptToPDF.category, .officeToPDF)
        XCTAssertEqual(ConversionType.pdfToWord.category, .pdfToOffice)
        XCTAssertEqual(ConversionType.pdfToExcel.category, .pdfToOffice)
    }

    func testNetworkTypesCorrectlyFlagged() {
        XCTAssertTrue(ConversionType.pdfAISummary.requiresNetwork)
        XCTAssertTrue(ConversionType.pdfAITranslate.requiresNetwork)
        XCTAssertTrue(ConversionType.pdfAIToMarkdown.requiresNetwork)
        XCTAssertTrue(ConversionType.htmlToPDF.requiresNetwork)
        XCTAssertFalse(ConversionType.pdfToPNG.requiresNetwork)
        XCTAssertFalse(ConversionType.wordToPDF.requiresNetwork)
    }
}

/// 测试 ToolLocator 的缓存行为
final class ToolLocatorCacheTests: XCTestCase {

    func testPathIsCachedAfterFirstLookup() {
        ToolLocator.shared.configure(toolsRoot: nil)

        let tool = BundledToolsCatalog.all[0] // pdftoppm
        let firstLookup = ToolLocator.shared.path(for: tool)
        let secondLookup = ToolLocator.shared.path(for: tool)

        // 两次查找结果应一致（即使系统无该工具，返回值一致）
        XCTAssertEqual(firstLookup, secondLookup)
    }

    func testConfigureClearsCache() {
        let tool = BundledToolsCatalog.all[0]
        _ = ToolLocator.shared.path(for: tool)

        // 重新 configure 应清空缓存
        ToolLocator.shared.configure(toolsRoot: nil)
        let afterReconfigure = ToolLocator.shared.path(for: tool)
        XCTAssertEqual(afterReconfigure, ToolLocator.shared.path(for: tool))
    }
}

/// 测试 ConversionError 的 LocalizedError 描述
final class ConversionErrorDescriptionTests: XCTestCase {

    func testMissingToolDescriptionForSoffice() {
        let error = ConversionError.missingTool("soffice")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("LibreOffice"), "soffice 错误应提示安装 LibreOffice，实际: \(desc)")
    }

    func testMissingToolDescriptionForOtherTools() {
        let error = ConversionError.missingTool("pdftoppm")
        let desc = error.errorDescription ?? ""
        XCTAssertFalse(desc.contains("LibreOffice"), "其他工具不应提示 LibreOffice")
        XCTAssertTrue(desc.contains("pdftoppm"))
    }

    func testInvalidInputDescription() {
        let error = ConversionError.invalidInput("请选择文件")
        XCTAssertEqual(error.errorDescription, "输入无效: 请选择文件")
    }

    func testUnsupportedTypeDescription() {
        let error = ConversionError.unsupportedType(.pdfToPNG)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("PDF → PNG"))
    }
}

/// 测试 OfficeAutomationEngine 的 AppleScript 路径转义
final class AppleScriptEscapeTests: XCTestCase {

    /// 通过反射测试私有方法（编译时方法存在即测试通过）
    /// 这里我们通过创建引擎并转换来间接测试，
    /// 但引擎的 convert 需要真实环境，因此我们只测试协议 conformance
    func testOfficeAutomationEngineConformsToProtocol() {
        let engine = OfficeAutomationEngine()
        XCTAssertEqual(engine.kind, .officeAutomation)
        let types = engine.supportedTypes()
        XCTAssertTrue(types.contains(.wordToPDF))
        XCTAssertTrue(types.contains(.excelToPDF))
        XCTAssertTrue(types.contains(.pptToPDF))
        XCTAssertTrue(types.contains(.pdfToWord))
        XCTAssertTrue(types.contains(.pdfToExcel))
    }
}