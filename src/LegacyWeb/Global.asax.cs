using System.Web.Mvc;
using System.Web.Routing;
using LegacyWeb.App_Start;

namespace LegacyWeb
{
    public class MvcApplication : System.Web.HttpApplication
    {
        protected void Application_Start()
        {
            AreaRegistration.RegisterAllAreas();
            RouteConfig.RegisterRoutes(RouteTable.Routes);
        }
    }
}
