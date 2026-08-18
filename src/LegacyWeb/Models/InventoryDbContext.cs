using System.Data.Entity;

namespace LegacyWeb.Models
{
    public sealed class InventoryDbContext : DbContext
    {
        public InventoryDbContext() : base("LegacyLab")
        {
            Database.SetInitializer<InventoryDbContext>(null);
        }

        public DbSet<Product> Products { get; set; }
    }
}
