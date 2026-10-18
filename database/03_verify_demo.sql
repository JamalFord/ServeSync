USE servesync;
SELECT user_id, full_name, role, account_status FROM Users;
SELECT payroll_id, user_id, clock_in, clock_out, hours_worked FROM Payroll ORDER BY payroll_id DESC LIMIT 10;
SELECT COUNT(*) AS active_sessions FROM Sessions;
