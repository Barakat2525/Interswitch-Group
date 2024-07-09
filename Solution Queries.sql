--View the Purchases Table
SELECT *
FROM Purchases;

''' To determine critical vendor billings, 
we need to find out the total billings 
for each vendor for the financial year '''

SELECT VendorName, SUM (Dollars) AS InvoiceTotal
FROM Purchases
GROUP BY VendorNumber

--Now we shall find out the average total billing

--Average of Total purchases per Vendor
SELECT AVG (InvoiceTotal) AS AveragePurchases
FROM(
-- Total purchases per Vendor
	SELECT VendorNumber, VendorName, SUM (Dollars) AS InvoiceTotal
	FROM Purchases
	GROUP BY VendorNumber
)

'''
From the above query, we figured out that
The total billing per vendor on average is
about 2,554,767.

Therefore we set our CRITICAL VENDOR criteria
to an arbitrary amount of 1,000,000 (One Million)
'''

-- Critical Vendor (Total billing above One Million)
SELECT VendorNumber, VendorName, SUM (Dollars) AS InvoiceTotal
FROM Purchases
GROUP BY VendorNumber
HAVING InvoiceTotal > 1000000
ORDER BY InvoiceTotal DESC

''' This means that less than 32% of our vendors are critical 
to the business according to our criteria '''

-- QUESTION 1(a)
-- AGGREGATE TABLE of Critical Vendors (Total billing above One Million)
CREATE TABLE DataPrep1_CriticalVendor AS
SELECT VendorNumber, VendorName, SUM (Dollars) AS InvoiceTotal
FROM Purchases
GROUP BY VendorNumber
HAVING InvoiceTotal > 1000000
ORDER BY InvoiceTotal DESC

-- QUESTION 1(b)
-- Top 10 Vendors by quantity purchased
CREATE TABLE DataPrep1_Top10VendorsbyQty AS
SELECT VendorName, SUM (Quantity) AS TotalPurchaseQty
FROM Purchases
GROUP BY VendorNumber
ORDER BY TotalPurchaseQty DESC
LIMIT 10

-- Top 10 Vendors by purchase value
CREATE TABLE DataPrep1_Top10VendorsbyPurchaseAmt AS
SELECT VendorName, SUM (Dollars) AS TotalPurchaseAmt
FROM Purchases
GROUP BY VendorNumber
ORDER BY TotalPurchaseAmt DESC
LIMIT 10

-- Top 10 Vendors with Shortest Average Lead time (DAYS)
-- Create a Table with CTE to get how long on average between PODate and ReceivingDate in DAYS
CREATE TABLE DataPrep1_Top10ShortestLeadTimeDays AS
WITH LeadTime AS (
    SELECT DISTINCT VendorNumber, PONumber, VendorName, PODate, ReceivingDate,
           AVG(julianday(ReceivingDate) - julianday(PODate)) AS AvgDeliveryDays
    FROM Purchases
	GROUP BY VendorNumber
)
-- Select Top 10 shortest lead time
SELECT DISTINCT VendorName, AvgDeliveryDays
FROM LeadTime
GROUP BY VendorNumber
ORDER BY AvgDeliveryDays ASC
LIMIT 10

'''
To know how products perform from season to season, we need the sales quantity per time (date).
Our derived sales table does not have a date column therefore we have to infer sales with purchases.

We assume that purchases are made based on selling rate.
'''

CREATE TABLE DataPrep1_SeasonalityAnalysis AS
WITH Seasonal AS (
	SELECT CAST(strftime ('%m', ReceivingDate)AS INT) AS ReceivingDate, Quantity, Classification
	FROM Purchases
)
SELECT 
	CASE
		WHEN ReceivingDate BETWEEN 3 AND 5 THEN 'Spring'
		WHEN ReceivingDate BETWEEN 6 AND 8 THEN 'Summer'
		WHEN ReceivingDate BETWEEN 9 AND 11 THEN 'Fall'
		ELSE 'Winter'
	END AS Seasons,
	CASE
		WHEN Classification = 1 THEN 'Spirit'
		WHEN Classification = 2 THEN 'Wine'
	END AS Classification,
	SUM (Quantity) AS SalesQty
FROM Seasonal
GROUP BY Seasons, Classification

------------------------------------------------------------------------------------------


-- View the products table
SELECT *
FROM Products

--We observed on the above table, that a lot of data are wrongly entered into some columns.
-- We make more enquiries below
SELECT *
FROM Products
WHERE Classification NOT IN	(1,2)

--Identifying the columns that we consider to be most crucial to this table,
-- We write the query below to ensure their data validity
SELECT *
FROM Products
WHERE Classification IN	(1,2) 
AND Description NOTNULL
AND Price > 0
AND Size NOTNULL

-- We have only 12,259 viable rows in the Products Table 
SELECT COUNT (*) AS ValidRows
FROM Products
WHERE Classification IN	(1,2) 
AND Description NOTNULL
AND Price > 0
AND Size NOTNULL

-- We will now load this rows into a new table which will be our valid products TABLE
CREATE TABLE DataPrep2_Products AS
SELECT *
FROM Products
WHERE Classification IN	(1,2) 
AND Description NOTNULL
AND Price > 0
AND Size NOTNULL;


'''
Here, we have been asked to make analysis based on sales figures, 
but we have not been provided with a SALES table.
We shall therefore have to derive our sales figures from the 
tables we have been provided with.
We have a begining stock table, a purchases table and a closing stock table. 
We will use these 3 tables to arrive at our sales quantities with the following formular:
(Begining stock + Purchases) - Closing stock.

Since the FULL OUTER JOIN function is not available in SQLite,
We shall attempt to achieve the same result with a UNION ALL function.
'''

--Please read script according to the numbers provided for clearer understanding.

--Create a table.

--The following block sums the onhand column, also the quantity column. 
--Then creates a new column TOTAL STOCK which is the addition of the 
--OpeningStock and Quantity purchased''' --------------------------------------------(2)
CREATE TABLE DerivedSalesQty AS
WITH TotalStockAvailable AS (
    SELECT
        InventoryId, Brand,
        SUM(onHand) AS TotalOpeningStock,
        SUM(Quantity) AS TotalPurchaseQty,
        SUM(onHand) + SUM(Quantity) AS TotalStock
    FROM (
	--Below, we select the necessary columns from the OpeningStock Table,
	--and UNION ALL with the purchases table. We have hard-coded zero (0) 
	--into the columns that exists in one table but not in the other.'''--............... (1)
        SELECT InventoryId, Brand, Description, onHand, 0 AS Quantity 
		FROM OpeningStock
        UNION ALL
        SELECT InventoryId, Brand, Description, 0 AS onHand, Quantity 
		FROM Purchases
    ) AS OpeningAndPurchasedStock
    GROUP BY InventoryId
)
	--Below, we join the Closing stock table to the Total Stock Table and 
	--add a new column by subtracting the closing stock from the 
	--stock available throughout the financial year, to arrive at the 
	--Total quantity that must have been sold in the year.''' -- -------------------------(3)
SELECT
    t.InventoryId, t.Brand,
    t.TotalOpeningStock,
    t.TotalPurchaseQty,
    t.TotalStock,
    COALESCE(c.onHand, 0) AS ClosingStockQty,
	-- This defines how NULL (0) will be handled when calculating TotalSalesQty.
    CASE
        WHEN c.onHand IS NULL THEN t.TotalStock
        ELSE t.TotalStock - c.onHand
    END AS TotalSalesQty
FROM TotalStockAvailable t
LEFT JOIN ClosingStock c 
ON t.InventoryId = c.InventoryId;

-- Since we now have Sales Qty, we can go a step further to have a table for
-- Sales with necessary Sales and Profit related columns
CREATE TABLE DataPrep2_Sales AS
SELECT pr.Brand, pr.Description,
	pr.PurchasePrice AS CostPrice,
	pr.Price AS SellingPrice,
	pr.Price - pr.PurchasePrice AS Profit, 
	sq.TotalSalesQty AS QtySold,
	sq.TotalSalesQty * pr.Price AS SalesAmount,
	sq.TotalSalesQty * (pr.Price - pr.PurchasePrice) AS TotalProfit
FROM DerivedSalesQty sq
INNER JOIN DataPrep2_Products pr
ON sq.Brand = pr.Brand

-------------------------------------------------------------------------------------------


--- Question 3 (a)
-- Total Sales(Dollars)
SELECT SUM(s.QtySold) AS GrandSalesQty, 
		SUM(s.SalesAmount )AS GrandSalesAmount,
		SUM (s.TotalProfit) AS GrandTotalProfit
FROM DataPrep2_Sales s
INNER JOIN DataPrep2_Products p ON s.Brand = p.Brand

-- Percentage Breakdown for Wine & Spirits
WITH BrandSalesAmount AS ( -- Select all sales amount for all brands
	SELECT p.Classification, s.Brand, s.SalesAmount
	FROM DataPrep2_Sales s
	INNER JOIN DataPrep2_Products p ON s.Brand = p.Brand
	)
SELECT -- replace classification numbers with Classification names
	CASE
		WHEN Classification = 1 THEN 'Spirit'
		WHEN Classification = 2 THEN 'Wine'
	END AS Classification,	
	SUM (SalesAmount) AS SalesAmount,
	100* SUM (SalesAmount) / -- multiply each Classification by 100 and divide by Grand Total
	(SELECT SUM (SalesAmount) FROM BrandSalesAmount) 
	AS Percentage
FROM BrandSalesAmount
GROUP BY Classification


--- Question 3 (b)
--- Most Popular sizes based on Sales Amount.
SELECT 
	CASE
		WHEN p.Classification = 1 THEN 'Spirit'
		WHEN p.Classification = 2 THEN 'Wine'
	END AS Classification,
	p.Size, MAX(s.SalesAmount) AS HighestSalesAmount
FROM DataPrep2_Sales s
INNER JOIN DataPrep2_Products p ON s.Brand = p.Brand
GROUP BY Classification


--- Most Popular sizes based on Sales Quantity.
SELECT 
	CASE
		WHEN p.Classification = 1 THEN 'Spirit'
		WHEN p.Classification = 2 THEN 'Wine'
	END AS Classification,
	p.Size, MAX(s.QtySold) AS HighestQtySold
FROM DataPrep2_Sales s
INNER JOIN DataPrep2_Products p ON s.Brand = p.Brand
GROUP BY Classification

-- Stores with Highest Avgerage Price for Spirit & Wine
WITH AvgStorePrices AS (
	SELECT 
		CASE
			WHEN p.Classification = 1 THEN 'Spirit'
			WHEN p.Classification = 2 THEN 'Wine'
		END AS Classification,
		p.Store, p.Brand, AVG(pr.Price) AS AvgSalesPrice
	FROM Purchases p
	INNER JOIN DataPrep2_Products pr
	ON pr.Brand = p.Brand
	GROUP BY p.Store
	)
SELECT Store, Classification, MAX(AvgSalesPrice) AS HighestAvgPrice
FROM AvgStorePrices
GROUP BY Classification


-- Stores with Lowest Avgerage Price for Spirit & Wine
WITH AvgStorePrices AS (
	SELECT 
		CASE
			WHEN p.Classification = 1 THEN 'Spirit'
			WHEN p.Classification = 2 THEN 'Wine'
		END AS Classification,
		p.Store, p.Brand, AVG(pr.Price) AS AvgSalesPrice
	FROM Purchases p
	INNER JOIN DataPrep2_Products pr
	ON pr.Brand = p.Brand
	GROUP BY p.Store
	)
SELECT Store, Classification, MIN(AvgSalesPrice) AS LowestAvgPrice
FROM AvgStorePrices
GROUP BY Classification