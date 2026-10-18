-- ServeSync section 7. MySQL 8.0.16+ (CHECK constraints enforced).
-- Fresh schema only: does not drop or overwrite existing tables.
CREATE DATABASE IF NOT EXISTS servesync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE servesync;
CREATE TABLE Users (
 user_id INT AUTO_INCREMENT PRIMARY KEY,
 full_name VARCHAR(100) NOT NULL,
 access_code VARCHAR(255) NOT NULL COMMENT 'Salted scrypt hash, never a plaintext PIN',
 pin_lookup CHAR(64) NOT NULL UNIQUE COMMENT 'HMAC-SHA256 using server secret; PINs are unique',
 role VARCHAR(30) NOT NULL,
 account_status VARCHAR(20) NOT NULL DEFAULT 'Active',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK (role IN ('FOH Staff','Manager','Administrator')),
 CHECK (account_status IN ('Active','Inactive'))
) ENGINE=InnoDB;
CREATE TABLE Payroll (
 payroll_id INT AUTO_INCREMENT PRIMARY KEY,
 user_id INT NOT NULL,
 clock_in DATETIME NOT NULL,
 clock_out DATETIME NULL,
 hours_worked DECIMAL(6,2) NULL,
 hourly_rate DECIMAL(8,2) NOT NULL DEFAULT 0,
 gross_pay DECIMAL(10,2) NULL,
 payment_status VARCHAR(30) NOT NULL DEFAULT 'Pending',
 FOREIGN KEY (user_id) REFERENCES Users(user_id),
 CHECK (clock_out IS NULL OR clock_out >= clock_in),
 CHECK (hourly_rate >= 0),
 CHECK (payment_status IN ('Pending','Paid','Pending Correction'))
) ENGINE=InnoDB;
CREATE TABLE Sessions (
 token_hash CHAR(64) PRIMARY KEY,
 user_id INT NOT NULL UNIQUE,
 payroll_id INT NOT NULL UNIQUE,
 expires_at DATETIME NOT NULL,
 FOREIGN KEY (user_id) REFERENCES Users(user_id),
 FOREIGN KEY (payroll_id) REFERENCES Payroll(payroll_id),
 INDEX (expires_at)
) ENGINE=InnoDB;
CREATE TABLE Login_Attempts (
 client_key CHAR(64) PRIMARY KEY,
 window_start BIGINT NOT NULL,
 failures INT NOT NULL
) ENGINE=InnoDB;
CREATE TABLE User_Management_Lock (lock_id INT PRIMARY KEY);
INSERT INTO User_Management_Lock VALUES (1);
CREATE TABLE Customer_Orders (
 order_id INT AUTO_INCREMENT PRIMARY KEY,
 user_id INT NOT NULL,
 table_number INT NOT NULL,
 order_status VARCHAR(20) NOT NULL DEFAULT 'Active',
 total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
 order_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY (user_id) REFERENCES Users(user_id),
 CHECK (table_number > 0), CHECK (total_amount >= 0),
 CHECK (order_status IN ('Active','Completed','Cancelled'))
) ENGINE=InnoDB;
CREATE TABLE Menu_Items (
 menu_item_id INT AUTO_INCREMENT PRIMARY KEY,
 item_name VARCHAR(100) NOT NULL,
 price DECIMAL(10,2) NOT NULL,
 available BOOLEAN NOT NULL DEFAULT TRUE,
 CHECK (price >= 0)
) ENGINE=InnoDB;
CREATE TABLE Order_Items (
 order_item_id INT AUTO_INCREMENT PRIMARY KEY,
 order_id INT NOT NULL,
 menu_item_id INT NOT NULL,
 quantity INT NOT NULL,
 unit_price DECIMAL(10,2) NOT NULL COMMENT 'Price snapshot when ordered',
 modifications VARCHAR(255) NULL,
 FOREIGN KEY (order_id) REFERENCES Customer_Orders(order_id),
 FOREIGN KEY (menu_item_id) REFERENCES Menu_Items(menu_item_id),
 CHECK (quantity > 0), CHECK (unit_price >= 0)
) ENGINE=InnoDB;
CREATE TABLE Dining_Tables (
 table_number INT PRIMARY KEY,
 capacity INT NOT NULL,
 CHECK (table_number > 0), CHECK (capacity > 0)
) ENGINE=InnoDB;
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
 CHECK (party_size > 0), CHECK (end_time > reservation_time),
 CHECK (status IN ('Confirmed','Seated','Cancelled','No-Show')),
 INDEX (table_number,reservation_date,reservation_time)
) ENGINE=InnoDB;
CREATE TABLE Inventory (
 inventory_id INT AUTO_INCREMENT PRIMARY KEY,
 item_name VARCHAR(100) NOT NULL,
 category VARCHAR(50) NOT NULL,
 quantity DECIMAL(10,2) NOT NULL DEFAULT 0,
 unit VARCHAR(20) NOT NULL,
 reorder_level DECIMAL(10,2) NOT NULL DEFAULT 0,
 last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK (quantity >= 0), CHECK (reorder_level >= 0)
) ENGINE=InnoDB;
CREATE TABLE Inventory_Transactions (
 transaction_id INT AUTO_INCREMENT PRIMARY KEY,
 inventory_id INT NOT NULL,
 user_id INT NOT NULL,
 quantity_change DECIMAL(10,2) NOT NULL,
 reason VARCHAR(255) NOT NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY (inventory_id) REFERENCES Inventory(inventory_id),
 FOREIGN KEY (user_id) REFERENCES Users(user_id),
 CHECK (quantity_change <> 0)
) ENGINE=InnoDB;
