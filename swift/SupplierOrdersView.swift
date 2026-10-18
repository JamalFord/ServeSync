//
//  SupplierOrdersView.swift
//  ServeSyncLocal
//
//  Feature A: UC-05 - Manage Supplier Purchase Orders & Receive Deliveries
//  iOS 16+; Swift 5 language mode.
//

import SwiftUI

struct Supplier: Codable, Identifiable {
    let supplier_id: Int
    let supplier_name: String
    let contact_person: String
    let phone_number: String
    let email: String
    let product_category: String
    var id: Int { supplier_id }
}

struct PurchaseOrderItem: Codable, Identifiable {
    let item_id: Int
    let inventory_id: Int
    let item_name: String
    let quantity_ordered: Double
    var quantity_received: Double
    let unit_cost: Double
    let unit: String
    var id: Int { item_id }
    
    var remainingQuantity: Double {
        max(0, quantity_ordered - quantity_received)
    }
}

struct PurchaseOrder: Codable, Identifiable {
    let order_id: Int
    let supplier_id: Int
    let supplier_name: String
    let created_by_name: String
    let order_date: String
    var status: String // Pending, Partial, Received, Cancelled
    let total_amount: Double
    var items: [PurchaseOrderItem]
    var id: Int { order_id }
}

@MainActor final class SupplierOrdersViewModel: ObservableObject {
    @Published var suppliers: [Supplier] = []
    @Published var purchaseOrders: [PurchaseOrder] = []
    @Published var inventoryItems: [InventoryStockItem] = []
    @Published var busy = false
    @Published var error: String?
    @Published var successMessage: String?
    
    let baseURL: URL
    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        self.baseURL = baseURL
    }
    
    func loadData(token: String?) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            suppliers = try await request("suppliers", token: token)
            purchaseOrders = try await request("purchase-orders", token: token)
            inventoryItems = try await request("inventory", token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func createOrder(supplierId: Int, items: [(inventoryId: Int, qty: Double, cost: Double)], token: String?) async -> Bool {
        busy = true; error = nil; successMessage = nil
        defer { busy = false }
        do {
            let payload: [String: Any] = [
                "supplier_id": supplierId,
                "items": items.map { ["inventory_id": $0.inventoryId, "quantity_ordered": $0.qty, "unit_cost": $0.cost] }
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let newOrder: PurchaseOrder = try await postRaw("purchase-orders", data: jsonData, token: token)
            purchaseOrders.insert(newOrder, at: 0)
            successMessage = "Purchase Order #\(newOrder.order_id) created successfully."
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    func receiveDelivery(orderId: Int, receivedQuantities: [Int: Double], notes: String, token: String?) async -> Bool {
        busy = true; error = nil; successMessage = nil
        defer { busy = false }
        do {
            let requestId = UUID().uuidString
            let payload: [String: Any] = [
                "request_id": requestId,
                "notes": notes,
                "received_items": receivedQuantities.map { ["item_id": $0.key, "quantity_received": $0.value] }
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let updatedOrder: PurchaseOrder = try await postRaw("purchase-orders/\(orderId)/receive", data: jsonData, token: token)
            if let idx = purchaseOrders.firstIndex(where: { $0.id == orderId }) {
                purchaseOrders[idx] = updatedOrder
            }
            inventoryItems = try await request("inventory", token: token)
            successMessage = "Delivery received. Stock quantities updated in inventory."
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

struct SupplierOrdersView: View {
    @EnvironmentObject var session: ServeSyncSession
    @StateObject private var vm = SupplierOrdersViewModel()
    @State private var showingCreateOrder = false
    @State private var selectedStatus = "All"
    
    var filteredOrders: [PurchaseOrder] {
        if selectedStatus == "All" { return vm.purchaseOrders }
        return vm.purchaseOrders.filter { $0.status == selectedStatus }
    }
    
    var body: some View {
        List {
            Picker("Filter Status", selection: $selectedStatus) {
                ForEach(["All", "Pending", "Partial", "Received", "Cancelled"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            
            if let msg = vm.successMessage {
                Section { Text(msg).foregroundStyle(.green).font(.subheadline) }
            }
            if let err = vm.error {
                Section { Text(err).foregroundStyle(.red).font(.subheadline) }
            }
            
            Section("Purchase Orders (\(filteredOrders.count))") {
                if filteredOrders.isEmpty {
                    Text("No purchase orders found.").foregroundColor(.secondary)
                } else {
                    ForEach(filteredOrders) { order in
                        NavigationLink {
                            PurchaseOrderDetailView(order: order, vm: vm)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("PO #\(order.order_id)").font(.headline)
                                    Spacer()
                                    StatusBadge(status: order.status)
                                }
                                Text("Supplier: \(order.supplier_name)").font(.subheadline)
                                HStack {
                                    Text("Total: $\(String(format: "%.2f", order.total_amount))")
                                    Spacer()
                                    Text(order.order_date).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            Section("Approved Suppliers (\(vm.suppliers.count))") {
                ForEach(vm.suppliers) { sup in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sup.supplier_name).font(.subheadline).bold()
                        Text("\(sup.product_category) • \(sup.phone_number)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Supplier Purchasing (UC-05)")
        .toolbar {
            Button("New PO") { showingCreateOrder = true }
        }
        .sheet(isPresented: $showingCreateOrder) {
            CreatePurchaseOrderSheet(vm: vm)
        }
        .task {
            await vm.loadData(token: session.currentToken)
        }
    }
}

struct PurchaseOrderDetailView: View {
    @EnvironmentObject var session: ServeSyncSession
    let order: PurchaseOrder
    @ObservedObject var vm: SupplierOrdersViewModel
    @State private var showingReceiveSheet = false
    
    var body: some View {
        List {
            Section("Order Information") {
                LabeledContent("PO Number", value: "#\(order.order_id)")
                LabeledContent("Supplier", value: order.supplier_name)
                LabeledContent("Created By", value: order.created_by_name)
                LabeledContent("Date", value: order.order_date)
                LabeledContent("Status") { StatusBadge(status: order.status) }
                LabeledContent("Total Amount", value: "$\(String(format: "%.2f", order.total_amount))")
            }
            
            Section("Items Ordered & Received") {
                ForEach(order.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.item_name).font(.headline)
                        HStack {
                            Text("Ordered: \(String(format: "%.1f", item.quantity_ordered)) \(item.unit)")
                            Spacer()
                            Text("Received: \(String(format: "%.1f", item.quantity_received))")
                                .foregroundColor(item.quantity_received >= item.quantity_ordered ? .green : .orange)
                        }.font(.subheadline)
                        Text("Unit Cost: $\(String(format: "%.2f", item.unit_cost))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            
            if order.status == "Pending" || order.status == "Partial" {
                Section {
                    Button("Receive Delivery (Atomic Stock Update)") {
                        showingReceiveSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("PO #\(order.order_id)")
        .sheet(isPresented: $showingReceiveSheet) {
            ReceiveDeliverySheet(order: order, vm: vm)
        }
    }
}

struct ReceiveDeliverySheet: View {
    @EnvironmentObject var session: ServeSyncSession
    @Environment(\.dismiss) var dismiss
    let order: PurchaseOrder
    @ObservedObject var vm: SupplierOrdersViewModel
    @State private var receivedInputs: [Int: String] = [:]
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Enter Received Quantities") {
                    Text("Partial receipts add received items to inventory stock and leave the balance open.")
                        .font(.footnote).foregroundColor(.secondary)
                    
                    ForEach(order.items) { item in
                        VStack(alignment: .leading) {
                            Text(item.item_name).font(.subheadline).bold()
                            Text("Remaining to receive: \(String(format: "%.1f", item.remainingQuantity)) \(item.unit)")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("Qty Received", text: Binding(
                                get: { receivedInputs[item.id] ?? "" },
                                set: { receivedInputs[item.id] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                        }
                    }
                }
                
                Section("Delivery Notes") {
                    TextField("Invoice/Delivery notes (optional)", text: $notes)
                }
                
                Button("Commit Delivery to Inventory") {
                    Task {
                        var parsed: [Int: Double] = [:]
                        for (itemId, textVal) in receivedInputs {
                            if let val = Double(textVal), val > 0 {
                                parsed[itemId] = val
                            }
                        }
                        if await vm.receiveDelivery(orderId: order.order_id, receivedQuantities: parsed, notes: notes, token: session.currentToken) {
                            dismiss()
                        }
                    }
                }
                .disabled(vm.busy || receivedInputs.values.allSatisfy { Double($0) ?? 0 <= 0 })
            }
            .navigationTitle("Receive Delivery")
            .toolbar {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

struct CreatePurchaseOrderSheet: View {
    @EnvironmentObject var session: ServeSyncSession
    @Environment(\.dismiss) var dismiss
    @ObservedObject var vm: SupplierOrdersViewModel
    @State private var selectedSupplierId: Int = 0
    @State private var selectedInventoryId: Int = 0
    @State private var orderQty = ""
    @State private var unitCost = ""
    @State private var draftLines: [(inventoryId: Int, name: String, qty: Double, cost: Double)] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Supplier") {
                    Picker("Supplier", selection: $selectedSupplierId) {
                        Text("Select a supplier").tag(0)
                        ForEach(vm.suppliers) { Text($0.supplier_name).tag($0.supplier_id) }
                    }
                }
                
                Section("Add Inventory Items") {
                    Picker("Item", selection: $selectedInventoryId) {
                        Text("Select an item").tag(0)
                        ForEach(vm.inventoryItems) { Text("\($0.item_name) (\($0.unit))").tag($0.inventory_id) }
                    }
                    TextField("Quantity to order", text: $orderQty).keyboardType(.decimalPad)
                    TextField("Estimated unit cost ($)", text: $unitCost).keyboardType(.decimalPad)
                    
                    Button("Add Line Item") {
                        if let inv = vm.inventoryItems.first(where: { $0.inventory_id == selectedInventoryId }),
                           let q = Double(orderQty), q > 0,
                           let c = Double(unitCost), c >= 0 {
                            draftLines.append((inventoryId: inv.inventory_id, name: inv.item_name, qty: q, cost: c))
                            orderQty = ""
                            unitCost = ""
                            selectedInventoryId = 0
                        }
                    }
                    .disabled(selectedInventoryId == 0 || Double(orderQty) ?? 0 <= 0)
                }
                
                if !draftLines.isEmpty {
                    Section("Order Line Items") {
                        ForEach(Array(draftLines.enumerated()), id: \.offset) { idx, line in
                            HStack {
                                Text(line.name)
                                Spacer()
                                Text("\(String(format: "%.1f", line.qty)) @ $\(String(format: "%.2f", line.cost))")
                            }
                        }
                    }
                }
                
                Button("Submit Purchase Order") {
                    Task {
                        let lines = draftLines.map { (inventoryId: $0.inventoryId, qty: $0.qty, cost: $0.cost) }
                        if await vm.createOrder(supplierId: selectedSupplierId, items: lines, token: session.currentToken) {
                            dismiss()
                        }
                    }
                }
                .disabled(vm.busy || selectedSupplierId == 0 || draftLines.isEmpty)
            }
            .navigationTitle("New Purchase Order")
            .toolbar {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    var color: Color {
        switch status {
        case "Received": return .green
        case "Partial": return .orange
        case "Pending": return .blue
        case "Cancelled": return .red
        default: return .gray
        }
    }
    var body: some View {
        Text(status)
            .font(.caption).bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}
