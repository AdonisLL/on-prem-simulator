using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using LegacyWeb.Models;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace LegacyWeb.Tests
{
    [TestClass]
    public class ProductTests
    {
        [TestMethod]
        public void ProductRequiresSkuAndName()
        {
            var product = new Product();
            var results = new List<ValidationResult>();

            var valid = Validator.TryValidateObject(product, new ValidationContext(product), results, true);

            Assert.IsFalse(valid);
            Assert.AreEqual(2, results.Count);
        }

        [TestMethod]
        public void SeedCompatibleProductIsValid()
        {
            var product = new Product
            {
                Name = "Serial Cable",
                Sku = "SC-210",
                QuantityOnHand = 85,
                UnitPrice = 18.50m
            };
            var results = new List<ValidationResult>();

            var valid = Validator.TryValidateObject(product, new ValidationContext(product), results, true);

            Assert.IsTrue(valid);
            Assert.AreEqual(0, results.Count);
        }
    }
}
