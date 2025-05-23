//
//  AerospaceManager.swift
//  AeroBar
//
//  Created by Eric Stein on 24.05.25.
//

import Foundation

struct WorkspaceInfo {
    let allWorkspaces: [String]
    let focusedWorkspace: String
}

class AerospaceManager {
    enum AerospaceError: Error {
        case commandFailed(String)
        case noOutput
        case parseError
        case aerospaceNotFound
        case permissionDenied
        case timeout
        case cancelled
    }
    
    private var aerospacePath: String?
    private var currentOperation: Operation?
    
    init() {
        findAerospacePath()
    }
    
    private func findAerospacePath() {
        let possiblePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
            "/usr/bin/aerospace"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                if FileManager.default.isExecutableFile(atPath: path) {
                    aerospacePath = path
                    print("Found aerospace at: \(path)")
                    return
                }
            }
        }
        
        print("aerospace not found in common paths")
    }
    
    func getWorkspaceInfo(completion: @escaping (Result<WorkspaceInfo, AerospaceError>) -> Void) {
        guard let aerospacePath = aerospacePath else {
            completion(.failure(.aerospaceNotFound))
            return
        }
        
        // Cancel previous operation if running
        currentOperation?.cancel()
        
        // Create new operation
        let operation = BlockOperation()
        currentOperation = operation
        
        operation.addExecutionBlock { [weak self] in
            // Check if cancelled at start
            guard !operation.isCancelled else {
                DispatchQueue.main.async { completion(.failure(.cancelled)) }
                return
            }
            
            // Get all workspaces
            let allResult = self?.runQuickCommand("\(aerospacePath) list-workspaces --all")
            
            // Check if cancelled after first command
            guard !operation.isCancelled else {
                DispatchQueue.main.async { completion(.failure(.cancelled)) }
                return
            }
            
            switch allResult {
            case .success(let allWorkspaces):
                // Get focused workspace
                let focusedResult = self?.runQuickCommand("\(aerospacePath) list-workspaces --focused")
                
                // Check if cancelled after second command
                guard !operation.isCancelled else {
                    DispatchQueue.main.async { completion(.failure(.cancelled)) }
                    return
                }
                
                switch focusedResult {
                case .success(let focusedWorkspaces):
                    guard let focused = focusedWorkspaces.first else {
                        DispatchQueue.main.async { completion(.failure(.parseError)) }
                        return
                    }
                    
                    let info = WorkspaceInfo(
                        allWorkspaces: allWorkspaces,
                        focusedWorkspace: focused
                    )
                    
                    DispatchQueue.main.async { completion(.success(info)) }
                    
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                case .none:
                    print("none case reached")
                }
                
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
                
            case .none:
                DispatchQueue.main.async { completion(.failure(.noOutput)) }
            }
        }
        
        // Execute on background queue
        OperationQueue().addOperation(operation)
    }
    
    private func runQuickCommand(_ command: String) -> Result<[String], AerospaceError> {
        let task = Process()
        let pipe = Pipe()
        
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.environment = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"]
        
        do {
            try task.run()
            
            // Quick timeout check
            let startTime = Date()
            while task.isRunning && Date().timeIntervalSince(startTime) < 2.0 {
                usleep(10000) // 10ms
            }
            
            if task.isRunning {
                task.terminate()
                return .failure(.timeout)
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 {
                let lines = output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                
                return .success(lines)
            } else {
                return .failure(.commandFailed("Command failed"))
            }
            
        } catch {
            return .failure(.commandFailed("Failed to execute: \(error.localizedDescription)"))
        }
    }
}
