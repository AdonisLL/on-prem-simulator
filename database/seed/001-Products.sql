USE LegacyLab;
GO

MERGE dbo.Products AS target
USING
(
    VALUES
        (N'LT-100', N'Legacy Terminal', CAST(399.00 AS decimal(10,2)), 12),
        (N'SC-210', N'Serial Cable', CAST(18.50 AS decimal(10,2)), 85),
        (N'PR-400', N'Dot Matrix Printer', CAST(249.99 AS decimal(10,2)), 7),
        (N'BK-016', N'SQL Server 2016 Handbook', CAST(54.95 AS decimal(10,2)), 24)
) AS source(Sku, Name, UnitPrice, QuantityOnHand)
ON target.Sku = source.Sku
WHEN MATCHED THEN
    UPDATE SET Name = source.Name, UnitPrice = source.UnitPrice, QuantityOnHand = source.QuantityOnHand
WHEN NOT MATCHED THEN
    INSERT (Sku, Name, UnitPrice, QuantityOnHand)
    VALUES (source.Sku, source.Name, source.UnitPrice, source.QuantityOnHand);
GO
