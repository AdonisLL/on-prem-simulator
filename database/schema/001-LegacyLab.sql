SET NOCOUNT ON;
GO

IF DB_ID(N'LegacyLab') IS NULL
BEGIN
    CREATE DATABASE LegacyLab;
END;
GO

USE LegacyLab;
GO

IF OBJECT_ID(N'dbo.Products', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Products
    (
        Id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
        Name nvarchar(80) NOT NULL,
        Sku nvarchar(32) NOT NULL CONSTRAINT UQ_Products_Sku UNIQUE,
        UnitPrice decimal(10,2) NOT NULL,
        QuantityOnHand int NOT NULL,
        UpdatedUtc datetime2(0) NOT NULL CONSTRAINT DF_Products_UpdatedUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_Products_UpdatedUtc
ON dbo.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE product
        SET UpdatedUtc = SYSUTCDATETIME()
    FROM dbo.Products AS product
    INNER JOIN inserted AS changed ON changed.Id = product.Id;
END;
GO

IF DB_ID(N'LegacyReporting') IS NULL
BEGIN
    CREATE DATABASE LegacyReporting;
END;
GO

USE LegacyReporting;
GO

CREATE OR ALTER VIEW dbo.InventorySnapshot
AS
    SELECT Id, Sku, Name, QuantityOnHand, UpdatedUtc
    FROM LegacyLab.dbo.Products;
GO
