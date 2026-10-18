-- ============================================================================
-- ServeSync Sprint 3: Database Schema Extension
-- Four Additional Major Use Cases:
-- 1. UC-05: Supplier Purchasing & Delivery Receiving
-- 2. UC-11: Inventory Spoilage & Freshness Tracking
-- 3. UC-10: Job Applicants & Onboarding Management
-- 4. UC-12: Customer Service & Grievance Administration
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. UC-05: Suppliers & Supplier Orders
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Suppliers (
    supplier_id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL,
    product_category VARCHAR(100) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS Supplier_Orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT NOT NULL,
    created_by INT NOT NULL,
    order_date DATETIME NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending', -- Pending, Partial, Received, Cancelled
    CONSTRAINT fk_po_supplier FOREIGN KEY (supplier_id) REFERENCES Suppliers(supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_po_user FOREIGN KEY (created_by) REFERENCES Users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS Supplier_Order_Items (
    item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    inventory_id INT NOT NULL,
    quantity_ordered DECIMAL(10,2) NOT NULL,
    quantity_received DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    unit_cost DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_poi_order FOREIGN KEY (order_id) REFERENCES Supplier_Orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_poi_inventory FOREIGN KEY (inventory_id) REFERENCES Inventory(inventory_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS Delivery_Receipts (
    receipt_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    received_by INT NOT NULL,
    receipt_date DATETIME NOT NULL,
    request_id VARCHAR(64) UNIQUE NOT NULL, -- Idempotency token
    notes TEXT,
    CONSTRAINT fk_rcpt_order FOREIGN KEY (order_id) REFERENCES Supplier_Orders(order_id) ON DELETE RESTRICT,
    CONSTRAINT fk_rcpt_user FOREIGN KEY (received_by) REFERENCES Users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 2. UC-11: Inventory Spoilage
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Inventory_Spoilage (
    spoilage_id INT AUTO_INCREMENT PRIMARY KEY,
    inventory_id INT NOT NULL,
    quantity_spoiled DECIMAL(10,2) NOT NULL,
    reason VARCHAR(100) NOT NULL, -- Expired, Damaged Packaging, Prep Waste, Temp Fluctuation
    notes TEXT,
    recorded_by INT NOT NULL,
    occurred_at DATETIME NOT NULL,
    stock_before DECIMAL(10,2) NOT NULL,
    stock_after DECIMAL(10,2) NOT NULL,
    request_id VARCHAR(64) UNIQUE NOT NULL, -- Idempotency token
    CONSTRAINT fk_spoilage_inv FOREIGN KEY (inventory_id) REFERENCES Inventory(inventory_id) ON DELETE RESTRICT,
    CONSTRAINT fk_spoilage_user FOREIGN KEY (recorded_by) REFERENCES Users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 3. UC-10: Job Applicants & Hiring
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Job_Applicants (
    applicant_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    applied_position VARCHAR(100) NOT NULL,
    availability VARCHAR(100) NOT NULL,
    years_experience INT NOT NULL DEFAULT 0,
    resume_path VARCHAR(255),
    application_status VARCHAR(30) NOT NULL DEFAULT 'New', -- New, Reviewed, Interview, Rejected, Hired
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 4. UC-12: Customer Service Administration
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Customer_Service_Issues (
    issue_id INT AUTO_INCREMENT PRIMARY KEY,
    category VARCHAR(50) NOT NULL, -- Food Quality, Seating Delay, Billing, Service Staff, Cleanliness
    description TEXT NOT NULL,
    customer_contact VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'Open', -- Open, In Progress, Resolved
    reported_at DATETIME NOT NULL,
    assigned_to INT,
    resolution_notes TEXT,
    resolved_at DATETIME,
    CONSTRAINT fk_issue_user FOREIGN KEY (assigned_to) REFERENCES Users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
