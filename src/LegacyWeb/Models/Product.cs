using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace LegacyWeb.Models
{
    [Table("Products")]
    public class Product
    {
        public int Id { get; set; }

        [Required, StringLength(80)]
        public string Name { get; set; }

        [Required, StringLength(32)]
        public string Sku { get; set; }

        public decimal UnitPrice { get; set; }

        public int QuantityOnHand { get; set; }
    }
}
