using System;
using System.IO;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using LegacyWeb.Models;

namespace LegacyWeb.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            using (var database = new InventoryDbContext())
            {
                var products = database.Products.OrderBy(product => product.Name).ToList();
                Session["LastInventoryReadUtc"] = DateTime.UtcNow;
                ViewBag.ServerName = Environment.MachineName;
                ViewBag.LastReadUtc = Session["LastInventoryReadUtc"];
                return View(products);
            }
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Adjust(int id, int delta)
        {
            using (var database = new InventoryDbContext())
            {
                var product = database.Products.Single(productRow => productRow.Id == id);
                product.QuantityOnHand = Math.Max(0, product.QuantityOnHand + delta);
                database.SaveChanges();
            }

            return RedirectToAction("Index");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Upload(HttpPostedFileBase document)
        {
            if (document == null || document.ContentLength == 0)
            {
                ModelState.AddModelError("", "Choose a document to upload.");
                return Index();
            }

            var safeName = Path.GetFileName(document.FileName);
            var uploadRoot = Server.MapPath("~/App_Data/Uploads");
            Directory.CreateDirectory(uploadRoot);
            document.SaveAs(Path.Combine(uploadRoot, safeName));
            TempData["UploadResult"] = safeName + " was stored on " + Environment.MachineName + ".";
            return RedirectToAction("Index");
        }
    }
}
