// Add to the existing iOS app target. iOS 16+; Swift 5 language mode.
import SwiftUI
import Foundation
import Combine

struct Staff: Codable, Identifiable {
    let user_id: Int
    let full_name: String
    let role: String
    let account_status: String
    var id: Int { user_id }
}

struct ShiftStatusReply: Decodable {
    let is_clocked_in: Bool
    let clock_in_time: String?
    let hours_worked_today: Double?
}

private struct UserReply: Decodable { let user: Staff }
private struct LoginReply: Decodable {
    let token: String
    let user: Staff
    let shift_status: ShiftStatusReply?
}
private struct UsersReply: Decodable { let users: [Staff] }
private struct ErrorReply: Decodable { let error: String }
private struct MessageReply: Decodable { let message: String }

struct ServerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor final class ServeSyncSession: ObservableObject {
    @Published var user: Staff?
    @Published var users: [Staff] = []
    @Published var error: String?
    @Published var busy = false
    @Published var isClockedIn: Bool = false
    @Published var clockInTime: String?
    @Published var hoursToday: Double = 0.0
    
    // iOS Simulator on the same Mac. Physical iPad: change to the Mac's LAN IP.
    let baseURL: URL
    private(set) var currentToken: String?
    
    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        self.baseURL = baseURL
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let currentToken { req.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ServerError(message: "Invalid server response.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { currentToken = nil; user = nil; users = [] }
            let message = (try? JSONDecoder().decode(ErrorReply.self, from: data).error) ?? "Request failed (\(http.statusCode))."
            throw ServerError(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await action() } catch { self.error = error.localizedDescription }
    }
    
    func login(pin: String) async {
        await perform {
            let reply: LoginReply = try await request("login", method: "POST", body: ["pin": pin])
            currentToken = reply.token
            user = reply.user
            if let st = reply.shift_status {
                isClockedIn = st.is_clocked_in
                clockInTime = st.clock_in_time
                hoursToday = st.hours_worked_today ?? 0.0
            }
        }
    }
    
    // Client Requirement: Logging out ends session, does NOT end employee shift.
    func logout() async {
        await perform {
            let _: MessageReply = try await request("logout", method: "POST")
            currentToken = nil
            user = nil
            users = []
        }
    }
    
    // Client Requirement: Explicit employee Clock-In
    func clockIn() async {
        await perform {
            let reply: ShiftStatusReply = try await request("clock-in", method: "POST")
            isClockedIn = reply.is_clocked_in
            clockInTime = reply.clock_in_time
            hoursToday = reply.hours_worked_today ?? 0.0
        }
    }
    
    // Client Requirement: Explicit employee Clock-Out
    func clockOut() async {
        await perform {
            let reply: ShiftStatusReply = try await request("clock-out", method: "POST")
            isClockedIn = reply.is_clocked_in
            clockInTime = nil
            hoursToday = reply.hours_worked_today ?? 0.0
        }
    }
    
    func refreshShiftStatus() async {
        guard currentToken != nil else { return }
        await perform {
            let reply: ShiftStatusReply = try await request("shift-status")
            isClockedIn = reply.is_clocked_in
            clockInTime = reply.clock_in_time
            hoursToday = reply.hours_worked_today ?? 0.0
        }
    }
    
    func refresh() async {
        guard currentToken != nil else { return }
        await perform {
            let reply: UserReply = try await request("me")
            user = reply.user
        }
        await refreshShiftStatus()
    }
    
    func loadUsers() async {
        await perform {
            let reply: UsersReply = try await request("users")
            users = reply.users
        }
    }
    
    func save(id: Int?, name: String, role: String, pin: String, status: String) async -> Bool {
        var succeeded = false
        await perform {
            var body: [String: Any] = ["full_name": name, "role": role, "account_status": status]
            if !pin.isEmpty { body["pin"] = pin }
            let path = id.map { "users/\($0)" } ?? "users"
            let _: UserReply = try await request(path, method: id == nil ? "POST" : "PATCH", body: body)
            if id == user?.id && !pin.isEmpty { currentToken = nil; user = nil; users = [] }
            succeeded = true
        }
        if succeeded && user?.role == "Administrator" { await loadUsers() }
        return succeeded
    }
    
    func remove(_ staff: Staff) async {
        await perform {
            let _: UserReply = try await request("users/\(staff.id)", method: "DELETE")
        }
        if user != nil { await loadUsers() }
    }
    
    func endSession(_ staff: Staff) async {
        await perform {
            let _: MessageReply = try await request("users/\(staff.id)/end-session", method: "POST")
            if staff.id == user?.id { currentToken = nil; user = nil; users = [] }
        }
    }
}

struct ServeSyncUserManagementRoot: View {
    @StateObject private var session = ServeSyncSession()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        Group {
            if session.user == nil {
                StaffLoginView()
            } else {
                StaffDashboardView()
            }
        }
        .environmentObject(session)
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await session.refresh() } }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if !Task.isCancelled { await session.refresh() }
            }
        }
    }
}

struct StaffLoginView: View {
    @EnvironmentObject var session: ServeSyncSession
    @State private var pin = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("ServeSync Staff Access") {
                    SecureField("Enter Four-digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                    
                    Button("Log In to Session") {
                        Task {
                            await session.login(pin: pin)
                            pin = ""
                        }
                    }
                    .disabled(session.busy || pin.count != 4 || !pin.allSatisfy({ $0 >= "0" && $0 <= "9" }))
                }
                
                if let error = session.error {
                    Text(error).foregroundStyle(.red)
                }
                
                Section {
                    Text("Note: Logging in starts your app session. Per restaurant policy, shift Clock In and Clock Out must be selected explicitly on the dashboard.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("ServeSync")
        }
    }
}

struct StaffDashboardView: View {
    @EnvironmentObject var session: ServeSyncSession
    
    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    // Employee Info & Role Header
                    Section("Staff Profile") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.full_name).font(.headline)
                                Text(user.role).font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(user.account_status)
                                .font(.caption).bold()
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                    
                    // Explicit Shift Clock In / Clock Out Card (Client Requirement)
                    Section("Shift Time Tracking (UC-01)") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.isClockedIn ? "Currently Clocked In" : "Currently Clocked Out")
                                    .font(.subheadline).bold()
                                    .foregroundColor(session.isClockedIn ? .green : .secondary)
                                if let start = session.clockInTime {
                                    Text("Since: \(start)").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if session.isClockedIn {
                                Button("Clock Out") {
                                    Task { await session.clockOut() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(session.busy)
                            } else {
                                Button("Clock In") {
                                    Task { await session.clockIn() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(session.busy)
                            }
                        }
                        Text("Shifts persist across app logouts until explicit clock-out.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    
                    // Sprint 3 Implemented Major Native Features
                    if user.role == "Manager" || user.role == "Administrator" {
                        Section("Sprint 3 Core Restaurant Features") {
                            NavigationLink {
                                SupplierOrdersView()
                            } label: {
                                Label("Supplier Orders & Receiving (UC-05)", systemImage: "truck.box.fill")
                            }
                            
                            NavigationLink {
                                SpoilageLoggingView()
                            } label: {
                                Label("Inventory & Spoilage Log (UC-11)", systemImage: "exclamationmark.triangle.fill")
                            }
                        }
                    }
                    
                    // Administrator Security & User Management
                    if user.role == "Administrator" {
                        Section("Administration & Security (UC-08)") {
                            NavigationLink("Employee Directory & Roles") { StaffDirectoryView() }
                            NavigationLink("Change Administrator PIN") { StaffEditorView(staff: user) }
                        }
                    }
                    
                    // Session Logout
                    Section {
                        Button("Log Out (Close Session)", role: .destructive) {
                            Task { await session.logout() }
                        }
                        .disabled(session.busy)
                    }
                }
                
                if let error = session.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("\(session.user?.role ?? "Staff") Home")
            .refreshable {
                await session.refresh()
            }
        }
    }
}

struct StaffDirectoryView: View {
    @EnvironmentObject var session: ServeSyncSession
    @State private var search = ""
    @State private var role = "All"
    @State private var ascending = true
    
    var filtered: [Staff] {
        session.users.filter { (role == "All" || $0.role == role) && (search.isEmpty || $0.full_name.localizedCaseInsensitiveContains(search)) }
            .sorted { ascending ? $0.full_name < $1.full_name : $0.full_name > $1.full_name }
    }
    
    var body: some View {
        List {
            Picker("Role", selection: $role) {
                ForEach(["All", "FOH Staff", "Manager", "Administrator"], id: \.self) { Text($0) }
            }
            Toggle("Name A to Z", isOn: $ascending)
            ForEach(filtered) { staff in
                NavigationLink { StaffEditorView(staff: staff) } label: {
                    VStack(alignment: .leading) {
                        Text(staff.full_name)
                        Text("\(staff.role) • \(staff.account_status)").font(.caption)
                    }
                }.swipeActions {
                    Button("Deactivate", role: .destructive) { Task { await session.remove(staff) } }
                        .disabled(staff.id == session.user?.id || session.busy)
                }
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Employees")
        .searchable(text: $search)
        .toolbar { NavigationLink("Add User") { StaffEditorView(staff: nil) } }
        .task { await session.loadUsers() }
    }
}

struct StaffEditorView: View {
    @EnvironmentObject var session: ServeSyncSession
    @Environment(\.dismiss) var dismiss
    let staff: Staff?
    @State private var name: String
    @State private var role: String
    @State private var pin = ""
    @State private var status: String
    
    init(staff: Staff?) {
        self.staff = staff
        _name = State(initialValue: staff?.full_name ?? "")
        _role = State(initialValue: staff?.role ?? "FOH Staff")
        _status = State(initialValue: staff?.account_status ?? "Active")
    }
    
    var body: some View {
        Form {
            TextField("Employee full name", text: $name)
            Picker("Role", selection: $role) {
                ForEach(["FOH Staff", "Manager", "Administrator"], id: \.self) { Text($0) }
            }.disabled(staff?.id == session.user?.id)
            Picker("Status", selection: $status) {
                Text("Active").tag("Active"); Text("Inactive").tag("Inactive")
            }.disabled(staff?.id == session.user?.id)
            SecureField(staff == nil ? "Four-digit PIN" : "New PIN (leave blank to keep)", text: $pin).keyboardType(.numberPad)
            Text("Changing a PIN or deactivating an account ends its active session.").font(.footnote)
            
            Button("Save Employee") {
                Task {
                    if await session.save(id: staff?.id, name: name, role: role, pin: pin, status: status) { dismiss() }
                }
            }
            .disabled(session.busy || name.trimmingCharacters(in: .whitespaces).isEmpty || (staff == nil && pin.isEmpty))
            
            if let staff {
                Button("End Active Session", role: .destructive) { Task { await session.endSession(staff) } }
                    .disabled(session.busy)
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(staff == nil ? "Add Employee" : "Edit Employee")
    }
}
