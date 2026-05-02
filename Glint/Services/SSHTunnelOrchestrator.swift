//
//  SSHTunnelOrchestrator.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//

import Foundation

/// Orchestrates a background SSH process to establish a secure port-forwarding tunnel.
actor SSHTunnelOrchestrator {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    /// Establishes the tunnel and returns the local port it is bound to.
    func establishTunnel(config: SSHTunnelConfig, targetHost: String, targetPort: Int) async throws -> Int {
        if process != nil {
            terminate()
        }
        
        let sshProcess = Process()
        sshProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        // Use a dynamically assigned ephemeral port if localPort is 0
        let boundLocalPort = config.localPort == 0 ? 5433 : config.localPort
        
        var args = [
            "-N", // Do not execute a remote command (just forward ports)
            "-L", "\(boundLocalPort):\(targetHost):\(targetPort)",
            "-p", "\(config.sshPort)",
            "-o", "ExitOnForwardFailure=yes", // Fail immediately if port is in use
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new" // Automatically accept new hosts to prevent UI hangs
        ]
        
        // Auth Method Handling
        // If password auth is used, we rely on standard SSH agent / sshpass (though sshpass is not native).
        // For enterprise, keyFile or agent is preferred.
        // We assume the user has ssh-agent running or keys in ~/.ssh/.
        
        args.append("\(config.sshUser)@\(config.sshHost)")
        sshProcess.arguments = args
        
        let errPipe = Pipe()
        sshProcess.standardError = errPipe
        
        do {
            try sshProcess.run()
            self.process = sshProcess
            self.errorPipe = errPipe
            
            // Wait briefly to see if the process exits immediately (e.g., connection refused or port in use)
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            guard sshProcess.isRunning else {
                let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown SSH error"
                throw NSError(domain: "SSHTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "SSH Tunnel failed: \(errorString)"])
            }
            
            print("[Glint] Established SSH Tunnel: localhost:\(boundLocalPort) -> \(targetHost):\(targetPort) via \(config.sshHost)")
            return boundLocalPort
            
        } catch {
            terminate()
            throw error
        }
    }
    
    func terminate() {
        if let p = process {
            if p.isRunning {
                p.terminate()
                print("[Glint] Terminated SSH Tunnel process (PID: \(p.processIdentifier))")
            }
            process = nil
        }
        errorPipe = nil
        outputPipe = nil
    }
    
    deinit {
        // As a safeguard, ensure process is terminated if actor is deallocated
        if let p = process, p.isRunning {
            p.terminate()
        }
    }
}
