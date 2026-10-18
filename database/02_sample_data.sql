-- Run ONCE after 01_schema.sql on a new demo database.
USE servesync;
INSERT INTO Dining_Tables (table_number,capacity) VALUES (1,2),(2,4),(3,6);
INSERT INTO Menu_Items (item_name,price) VALUES ('Chicken Sandwich',12.50),('Vegetable Bowl',10.00),('Lemonade',3.00);
INSERT INTO Inventory (item_name,category,quantity,unit,reorder_level)
VALUES ('Chicken','Protein',25.00,'lbs',10.00),('Rice','Dry Goods',50.00,'lbs',15.00),('Lemons','Produce',5.00,'pieces',10.00);
-- No plaintext default admin PIN. Create initial admin using server.py --bootstrap.
