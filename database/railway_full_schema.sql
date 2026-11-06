-- ============================================================================
-- ServeSync Complete Relational Schema & Seed Data (MySQL 8.0+)
-- Optimized for Cloud Deployment on Railway / Aiven / Local MySQL
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- Drop existing tables to allow clean re-runs
DROP TABLE IF EXISTS Delivery_Receipts;
DROP TABLE IF EXISTS Supplier_Order_Items;
DROP TABLE IF EXISTS Supplier_Orders;
DROP TABLE IF EXISTS Suppliers;
DROP TABLE IF EXISTS Inventory_Spoilage;
DROP TABLE IF EXISTS Inventory_Transactions;
DROP TABLE IF EXISTS Inventory;
DROP TABLE IF EXISTS Order_Items;
DROP TABLE IF EXISTS Menu_Items;
DROP TABLE IF EXISTS Customer_Orders;
DROP TABLE IF EXISTS Reservations;
DROP TABLE IF EXISTS Dining_Tables;
DROP TABLE IF EXISTS Sessions;
DROP TABLE IF EXISTS Payroll;
DROP TABLE IF EXISTS Users;
DROP TABLE IF EXISTS Login_Attempts;
DROP TABLE IF EXISTS User_Management_Lock;
DROP TABLE IF EXISTS Job_Applicants;
DROP TABLE IF EXISTS Customer_Service_Issues;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 1. Core User Management & Locks (UC-01, UC-08)
-- ----------------------------------------------------------------------------
CREATE TABLE User_Management_Lock (
    lock_id INT PRIMARY KEY
) ENGINE=InnoDB;

INSERT INTO User_Management_Lock (lock_id) VALUES (1);

CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    access_code VARCHAR(255) NOT NULL COMMENT 'Salted hash of employee PIN',
    pin_lookup CHAR(64) NOT NULL UNIQUE COMMENT 'HMAC-SHA256 lookup token',
    role VARCHAR(30) NOT NULL,
    account_status VARCHAR(20) NOT NULL DEFAULT 'Active',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (role IN ('FOH Staff', 'Manager', 'Administrator')),
    CHECK (account_status IN ('Active', 'Inactive'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Payroll (
    payroll_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    clock_in DATETIME NOT NULL,
    clock_out DATETIME NULL,
    hours_worked DECIMAL(6,2) NULL,
    hourly_rate DECIMAL(8,2) NOT NULL DEFAULT 16.50,
    gross_pay DECIMAL(10,2) NULL,
    payment_status VARCHAR(30) NOT NULL DEFAULT 'Pending',
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    CHECK (clock_out IS NULL OR clock_out >= clock_in),
    CHECK (hourly_rate >= 0),
    CHECK (payment_status IN ('Pending', 'Paid', 'Pending Correction'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Sessions (
    token_hash CHAR(64) PRIMARY KEY,
    user_id INT NOT NULL,
    payroll_id INT NULL, -- Nullable because login does NOT automatically clock into a shift
    expires_at DATETIME NOT NULL,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (payroll_id) REFERENCES Payroll(payroll_id) ON DELETE SET NULL,
    INDEX (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Login_Attempts (
    client_key CHAR(64) PRIMARY KEY,
    window_start BIGINT NOT NULL,
    failures INT NOT NULL
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 2. Dining Tables & Reservations (UC-03)
-- ----------------------------------------------------------------------------
CREATE TABLE Dining_Tables (
    table_number INT PRIMARY KEY,
    capacity INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Available',
    CHECK (table_number > 0),
    CHECK (capacity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Reservations (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    guest_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    party_size INT NOT NULL,
    reservation_date DATE NOT NULL,
    reservation_time TIME NOT NULL,
    end_time TIME NOT NULL,
    table_number INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Confirmed',
    created_by INT NOT NULL,
    FOREIGN KEY (created_by) REFERENCES Users(user_id),
    FOREIGN KEY (table_number) REFERENCES Dining_Tables(table_number),
    CHECK (party_size > 0),
    CHECK (end_time > reservation_time),
    CHECK (status IN ('Confirmed', 'Seated', 'Cancelled', 'No-Show')),
    INDEX (table_number, reservation_date, reservation_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 3. Customer Dining Orders & Menu Items (UC-02)
-- ----------------------------------------------------------------------------
CREATE TABLE Menu_Items (
    menu_item_id INT AUTO_INCREMENT PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    available BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (price >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Customer_Orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    table_number INT NOT NULL,
    order_status VARCHAR(20) NOT NULL DEFAULT 'Active',
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    order_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (table_number) REFERENCES Dining_Tables(table_number),
    CHECK (table_number > 0),
    CHECK (total_amount >= 0),
    CHECK (order_status IN ('Active', 'In Prep', 'Completed', 'Cancelled'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Order_Items (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    menu_item_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    modifications VARCHAR(255) NULL,
    FOREIGN KEY (order_id) REFERENCES Customer_Orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (menu_item_id) REFERENCES Menu_Items(menu_item_id),
    CHECK (quantity > 0),
    CHECK (unit_price >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 4. Inventory & Spoilage Tracking (UC-04, UC-11)
-- ----------------------------------------------------------------------------
CREATE TABLE Inventory (
    inventory_id INT AUTO_INCREMENT PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    quantity DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    unit VARCHAR(20) NOT NULL,
    reorder_level DECIMAL(10,2) NOT NULL DEFAULT 10.00,
    unit_cost DECIMAL(10,2) NOT NULL DEFAULT 1.00,
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (quantity >= 0),
    CHECK (reorder_level >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Inventory_Transactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    inventory_id INT NOT NULL,
    user_id INT NOT NULL,
    quantity_change DECIMAL(10,2) NOT NULL,
    reason VARCHAR(100) NOT NULL,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inventory_id) REFERENCES Inventory(inventory_id),
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Inventory_Spoilage (
    spoilage_id INT AUTO_INCREMENT PRIMARY KEY,
    inventory_id INT NOT NULL,
    quantity_spoiled DECIMAL(10,2) NOT NULL,
    reason VARCHAR(100) NOT NULL,
    notes TEXT,
    recorded_by INT NOT NULL,
    occurred_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    stock_before DECIMAL(10,2) NOT NULL,
    stock_after DECIMAL(10,2) NOT NULL,
    request_id VARCHAR(64) UNIQUE NOT NULL,
    FOREIGN KEY (inventory_id) REFERENCES Inventory(inventory_id),
    FOREIGN KEY (recorded_by) REFERENCES Users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 5. Suppliers & Purchase Orders (UC-05)
-- ----------------------------------------------------------------------------
CREATE TABLE Suppliers (
    supplier_id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL,
    product_category VARCHAR(100) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Supplier_Orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT NOT NULL,
    created_by INT NOT NULL,
    order_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    FOREIGN KEY (supplier_id) REFERENCES Suppliers(supplier_id),
    FOREIGN KEY (created_by) REFERENCES Users(user_id),
    CHECK (status IN ('Pending', 'Partial', 'Received', 'Cancelled'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Supplier_Order_Items (
    item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    inventory_id INT NOT NULL,
    quantity_ordered DECIMAL(10,2) NOT NULL,
    quantity_received DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    unit_cost DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES Supplier_Orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (inventory_id) REFERENCES Inventory(inventory_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Delivery_Receipts (
    receipt_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    received_by INT NOT NULL,
    receipt_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    request_id VARCHAR(64) UNIQUE NOT NULL,
    notes TEXT,
    FOREIGN KEY (order_id) REFERENCES Supplier_Orders(order_id),
    FOREIGN KEY (received_by) REFERENCES Users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 6. Job Applicants & Customer Service (UC-10, UC-12)
-- ----------------------------------------------------------------------------
CREATE TABLE Job_Applicants (
    applicant_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    applied_position VARCHAR(100) NOT NULL,
    availability VARCHAR(100) NOT NULL,
    years_experience INT NOT NULL DEFAULT 0,
    resume_path VARCHAR(255),
    application_status VARCHAR(30) NOT NULL DEFAULT 'New',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (application_status IN ('New', 'Reviewed', 'Interview', 'Rejected', 'Hired'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Customer_Service_Issues (
    issue_id INT AUTO_INCREMENT PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    customer_contact VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'Open',
    reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_to INT,
    resolution_notes TEXT,
    resolved_at DATETIME,
    FOREIGN KEY (assigned_to) REFERENCES Users(user_id) ON DELETE SET NULL,
    CHECK (status IN ('Open', 'In Progress', 'Resolved'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- INITIAL SEED DATA FOR DEMO & PRESENTATION
-- ============================================================================

-- 1. Dining Tables
INSERT INTO Dining_Tables (table_number, capacity, status) VALUES
(1, 2, 'Available'),
(2, 4, 'Available'),
(3, 4, 'Available'),
(4, 6, 'Available'),
(5, 4, 'Available'),
(6, 2, 'Available'),
(7, 8, 'Available'),
(8, 4, 'Available');

-- 2. Menu Items
INSERT INTO Menu_Items (item_name, category, price, available) VALUES
('ServeSync Smash Burger', 'Entrees', 18.00, TRUE),
('Pan-Roasted Atlantic Salmon', 'Entrees', 26.50, TRUE),
('Wild Mushroom Risotto', 'Entrees', 22.00, TRUE),
('Truffle Parmesan Fries', 'Appetizers', 12.00, TRUE),
('Crispy Calamari', 'Appetizers', 15.50, TRUE),
('Smoked Hibiscus Spritz', 'Beverages', 9.50, TRUE),
('Craft Cold Brew & Tonic', 'Beverages', 6.00, TRUE),
('Warm Molten Lava Cake', 'Desserts', 11.00, TRUE);

-- 3. Inventory On-Hand Stock
INSERT INTO Inventory (item_name, category, quantity, unit, reorder_level, unit_cost) VALUES
('Ground Angus Beef', 'Meat', 38.50, 'lbs', 15.00, 5.20),
('Fresh Atlantic Salmon Fillets', 'Seafood', 18.00, 'lbs', 10.00, 11.50),
('Vine-Ripened Tomatoes', 'Produce', 8.50, 'lbs', 12.00, 1.80),
('Artisan Brioche Buns', 'Bakery', 56.00, 'units', 24.00, 0.85),
('Aged White Cheddar Slices', 'Dairy', 14.00, 'lbs', 5.00, 4.25),
('Russet Potatoes', 'Produce', 65.00, 'lbs', 25.00, 0.65),
('Cleaned Calamari Tubes', 'Seafood', 12.00, 'lbs', 8.00, 7.40);

-- 4. Approved Suppliers
INSERT INTO Suppliers (supplier_name, contact_person, phone_number, email, product_category) VALUES
('Metro Farm Produce Co.', 'Dave Miller', '404-555-0199', 'orders@metrofarm.com', 'Fresh Produce & Herbs'),
('Buckhead Prime Meats', 'Sarah Jenkins', '404-555-0245', 'sales@buckheadmeats.com', 'Beef & Poultry'),
('Atlantic Seafood Wholesalers', 'Carlos Ortiz', '404-555-0388', 'carlos@atlanticseafood.com', 'Fresh Seafood');
