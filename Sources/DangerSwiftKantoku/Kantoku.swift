//
//  Kantoku.swift
//  
//
//  Created by 史 翔新 on 2022/02/10.
//

import Foundation
import XCResultKit
import Danger

public struct Kantoku {
    
    let workingDirectoryPath: String
    
    private let markdownCommentExecutor: (_ comment: String) -> Void
    
    private let inlineCommentExecutor: (_ comment: String, _ filePath: String, _ lineNumber: Int) -> Void
    private let normalCommentExecutor: (_ comment: String) -> Void
    
    private let inlineWarningExecutor: (_ comment: String, _ filePath: String, _ lineNumber: Int) -> Void
    private let normalWarningExecutor: (_ comment: String) -> Void
    
    private let inlineFailureExecutor: (_ comment: String, _ filePath: String, _ lineNumber: Int) -> Void
    private let normalFailureExecutor: (_ comment: String) -> Void
    
    init(
        workingDirectoryPath: String,
        markdownCommentExecutor: @escaping (_ comment: String) -> Void,
        inlineCommentExecutor: @escaping (_ comment: String, _ filePath: String, _ lineNumber: Int) -> Void,
        normalCommentExecutor: @escaping (_ comment: String) -> Void,
        inlineWarningExecutor: @escaping (_ comment: String, _ filePath: String, _ lineNumber: Int) -> Void,
        normalWarningExecutor: @escaping (_ comment: String) -> Void,
        inlineFailureExecutor: @escaping (_ comment: String, _ filePath: String, _ lineNumber: Int) -> Void,
        normalFailureExecutor: @escaping (_ comment: String) -> Void
    ) {
        self.workingDirectoryPath = workingDirectoryPath
        self.markdownCommentExecutor = markdownCommentExecutor
        self.inlineCommentExecutor = inlineCommentExecutor
        self.normalCommentExecutor = normalCommentExecutor
        self.inlineWarningExecutor = inlineWarningExecutor
        self.normalWarningExecutor = normalWarningExecutor
        self.inlineFailureExecutor = inlineFailureExecutor
        self.normalFailureExecutor = normalFailureExecutor
    }
    
}

extension Kantoku {
    
    func markdown(_ comment: String) {
        markdownCommentExecutor(comment)
    }
    
    func comment(_ comment: String, to filePath: String, at lineNumber: Int) {
        inlineCommentExecutor(comment, filePath, lineNumber)
    }
    
    func comment(_ comment: String) {
        normalCommentExecutor(comment)
    }
    
    func warn(_ warning: String, to filePath: String, at lineNumber: Int) {
        inlineWarningExecutor(warning, filePath, lineNumber)
    }
    
    func warn(_ warning: String) {
        normalWarningExecutor(warning)
    }
    
    func fail(_ failure: String, to filePath: String, at lineNumber: Int) {
        inlineFailureExecutor(failure, filePath, lineNumber)
    }
    
    func fail(_ failure: String) {
        normalFailureExecutor(failure)
    }
    
}

public typealias File = String
extension File {
    var finalFileName: String {
        return self.components(separatedBy: "/").last ?? ""

    }
}

extension Kantoku {
    
    public enum WariningFilter {
        case all
        case modifiedAndCreatedFiles
        case files([File])
    }
    
    private func postIssuesIfNeeded(from resultFile: XCResultFile, configuration: XCResultParsingConfiguration, warnFor: WariningFilter = .all) {
        
        if configuration.needsIssues {
            
            guard let issues = resultFile.getInvocationRecord()?.issues else {
                warn("Failed to get invocation record from \(resultFile.url.absoluteString)")
                return
            }

            var targetFileNames: [String]? = nil
            switch warnFor {
            case .all : break
            case .files(let files) :
                targetFileNames = files.map{ $0.finalFileName }
            case .modifiedAndCreatedFiles :
                let allFilePaths = Danger().git.modifiedFiles + Danger().git.createdFiles
                targetFileNames = allFilePaths.map { $0.finalFileName }
            }

            if configuration.parseBuildWarnings {
                post(issues.warningSummaries, as: .warning, targetFilesNmes: targetFileNames)
            }
            
            if configuration.parseBuildErrors {
                post(issues.errorSummaries, as: .failure)
            }
            
            if configuration.parseAnalyzerWarnings {
                post(issues.analyzerWarningSummaries, as: .warning)
            }
            
            if configuration.parseTestFailures {
                post(issues.testFailureSummaries, as: .failure)
            }
            
        }
        
    }
    
    private func postCoverageIfNeeded(from resultFile: XCResultFile, configuration: XCResultParsingConfiguration) {
        
        if let coverageAcceptanceDecision = configuration.codeCoverageRequirement.acceptanceDecision {
            
            guard let coverage = resultFile.getCodeCoverage() else {
                warn("Failed to get coverage from \(resultFile.url.absoluteString)")
                return
            }
            
            post(coverage, as: coverageAcceptanceDecision)
            
        }
        
    }
    
    public func parseXCResultFile(at filePath: String, configuration: XCResultParsingConfiguration, warnFor: WariningFilter) {
        
        let resultFile = XCResultFile(url: .init(fileURLWithPath: filePath))
        
        postIssuesIfNeeded(from: resultFile, configuration: configuration, warnFor: warnFor)
        postCoverageIfNeeded(from: resultFile, configuration: configuration)
        
    }
    
}

extension XCResultParsingConfiguration.CodeCoverageRequirement {
    
    var acceptanceDecision: ((Double) -> Kantoku.CoverageAcceptance)? {
        switch self {
        case .none:
            return nil
            
        case .required(let threshold):
            return { coverage in
                if coverage >= threshold.recommended {
                    return .good
                } else if coverage >= threshold.acceptable {
                    return .acceptable
                } else {
                    return .reject
                }
            }
        }
    }
    
}
