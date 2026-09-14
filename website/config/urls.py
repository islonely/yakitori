from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path

from config import views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("healthz", views.healthz, name="healthz"),

    # Authenticated account area (HTML).
    path("dashboard/", include("dashboard.urls")),

    # Identity: sign in/up/out and device approval (HTML).
    path("", include("accounts.urls")),

    # Public profiles and dashboard profile/privacy pages (HTML).
    path("", include("profiles.urls")),

    # Commerce: checkout pages and the provider webhook.
    path("", include("commerce.urls")),

    # Licensing: dashboard license/installation pages.
    path("", include("licensing.urls")),

    # Versioned JSON API.
    path("v1/", include("accounts.api_urls")),
    path("v1/", include("profiles.api_urls")),
    path("v1/", include("commerce.api_urls")),
    path("v1/", include("licensing.api_urls")),

    # Public marketing and legal pages (catch-all, keep last).
    path("", include("web.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

handler404 = "config.views.not_found"
handler500 = "config.views.server_error"
