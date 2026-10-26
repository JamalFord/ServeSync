//
//  SpoilageLoggingView.swift
//  ServeSyncLocal
//
//  Feature B: UC-11 - Record & Track Inventory Spoilage
//  iOS 16+; Swift 5 language mode.
//

import SwiftUI
import Foundation
import Combine

struct InventoryStockItem: Codable, Identifiable {
    let inventory_id: Int
    let item_name: String
    let category: String
    var quantity: Double
    let unit: String
    let reorder_level: Double
    var id: Int { inventory_id }
}

struct SpoilageRecord: Codable, Identifiable {
    let spoilage_id: Int
    let inventory_id: Int
    let item_name: String
    let quantity_spoiled: Double
    let unit: String
    let reason: String
    let recorded_by_name: String
    let occurred_at: String
    let stock_before: Double
    let stock_after: Double
    var id: Int { spoilage_id }
}

@MainActor final class SpoilageViewModel: ObservableObject {
    @Published var inventory: [InventoryStockItem] = []
    @Published var spoilageHistory: [SpoilageRecord] = []
    @Published var busy = false
    @Published var error: String?
    @Published var successMessage: String?
    
    let baseURL: URL
    init(baseURL: URL = ServeSyncConfig.defaultBaseURL) {
        self.baseURL = baseURL
    }
    
    func loadData(token: String?) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            inventory = try await request("inventory", token: token)
            spoilageHistory = try await request("inventory/spoilage", token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func recordSpoilage(inventoryId: Int, quantity: Double, reason: String, notes: String, token: String?) async -> Bool {
        busy = true; error = nil; successMessage = nil
        defer { busy = false }
        do {
            let requestId = UUID().uuidString
            let payload: [String: Any] = [
                "request_id": requestId,
                "inventory_id": inventoryId,
                "quantity": quantity,
                "reason": reason,
                "notes": notes
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let newRecord: SpoilageRecord = try await postRaw("inventory/spoilage", data: jsonData, token: token)
            spoilageHistory.insert(newRecord, at: 0)
            
            // Update local stock item
            if let idx = inventory.firstIndex(where: { $0.id == inventoryId }) {
                inventory[idx].quantity = newRecord.stock_after
            }
            successMessage = "Deducted \(String(format: "%.1f", quantity)) \(newRecord.unit) from inventory. Spoilage logged."
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    private func request<T: Decodable>(_ path: String, token: String?) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Failed to fetch data."
            throw ServerError(message: msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func postRaw<T: Decodable>(_ path: String, data: Data, token: String?) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = data
        let (resData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: resData))?["error"] ?? "Request failed."
            throw ServerError(message: msg)
        }
        return try JSONDecoder().decode(T.self, from: resData)
    }
}

struct SpoilageLoggingView: View {
    @EnvironmentObject var session: ServeSyncSession
    @StateObject private var vm = SpoilageViewModel()
    @State private var showingRecordSheet = false
    
    var body: some View {
        List {
            if let msg = vm.successMessage {
                Section { Text(msg).foregroundStyle(.green).font(.subheadline) }
            }
            if let err = vm.error {
                Section { Text(err).foregroundStyle(.red).font(.subheadline) }
            }
            
            Section("Current Inventory Stock") {
                ForEach(vm.inventory) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.item_name).font(.subheadline).bold()
                            Text(item.category).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(String(format: "%.1f", item.quantity)) \(item.unit)")
                                .font(.subheadline)
                                .foregroundColor(item.quantity <= item.reorder_level ? .red : .primary)
                            if item.quantity <= item.reorder_level {
                                Text("Low Stock").font(.caption2).foregroundColor(.red).bold()
                            }
                        }
                    }
                }
            }
            
            Section("Recent Spoilage Records (\(vm.spoilageHistory.count))") {
                if vm.spoilageHistory.isEmpty {
                    Text("No spoilage entries recorded.").foregroundColor(.secondary)
                } else {
                    ForEach(vm.spoilageHistory) { rec in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rec.item_name).font(.headline)
                                Spacer()
                                Text("-\(String(format: "%.1f", rec.quantity_spoiled)) \(rec.unit)")
                                    .foregroundColor(.red).bold()
                            }
                            HStack {
                                Text("Reason: \(rec.reason)").font(.subheadline)
                                Spacer()
                                Text("By: \(rec.recorded_by_name)").font(.caption).foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Stock: \(String(format: "%.1f", rec.stock_before)) → \(String(format: "%.1f", rec.stock_after)) \(rec.unit)")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(rec.occurred_at).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventory Spoilage (UC-11)")
        .toolbar {
            Button("Log Spoilage") { showingRecordSheet = true }
        }
        .sheet(isPresented: $showingRecordSheet) {
            RecordSpoilageSheet(vm: vm)
        }
        .task {
            await vm.loadData(token: session.currentToken)
        }
    }
}

struct RecordSpoilageSheet: View {
    @EnvironmentObject var session: ServeSyncSession
    @Environment(\.dismiss) var dismiss
    @ObservedObject var vm: SpoilageViewModel
    
    @State private var selectedInventoryId: Int = 0
    @State private var quantityStr = ""
    @State private var selectedReason = "Expired"
    @State private var notes = ""
    
    let reasons = ["Expired", "Damaged Packaging", "Dropped / Contaminated", "Kitchen Prep Waste", "Temperature Fluctuation"]
    
    var selectedItem: InventoryStockItem? {
        vm.inventory.first(where: { $0.id == selectedInventoryId })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Affected Item") {
                    Picker("Inventory Item", selection: $selectedInventoryId) {
                        Text("Select an item").tag(0)
                        ForEach(vm.inventory) { item in
                            Text("\(item.item_name) (On Hand: \(String(format: "%.1f", item.quantity)) \(item.unit))")
                                .tag(item.inventory_id)
                        }
                    }
                }
                
                Section("Quantity & Reason") {
                    HStack {
                        TextField("Spoiled Quantity", text: $quantityStr)
                            .keyboardType(.decimalPad)
                        if let item = selectedItem {
                            Text(item.unit).foregroundColor(.secondary)
                        }
                    }
                    
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(reasons, id: \.self) { Text($0) }
                    }
                    
                    TextField("Additional Notes (optional)", text: $notes)
                }
                
                if let item = selectedItem, let qty = Double(quantityStr), qty > item.quantity {
                    Section {
                        Text("Error: Spoiled quantity exceeds current on-hand stock (\(String(format: "%.1f", item.quantity)) \(item.unit)).")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
                
                Button("Commit Spoilage (Atomic Stock Deduction)") {
                    Task {
                        guard let qty = Double(quantityStr), qty > 0 else { return }
                        if await vm.recordSpoilage(
                            inventoryId: selectedInventoryId,
                            quantity: qty,
                            reason: selectedReason,
                            notes: notes,
                            token: session.currentToken
                        ) {
                            dismiss()
                        }
                    }
                }
                .disabled(
                    vm.busy ||
                    selectedInventoryId == 0 ||
                    Double(quantityStr) ?? 0 <= 0 ||
                    (selectedItem != nil && (Double(quantityStr) ?? 0) > (selectedItem?.quantity ?? 0))
                )
            }
            .navigationTitle("Record Spoilage")
            .toolbar {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
