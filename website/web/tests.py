from django.test import TestCase
from django.urls import reverse


class HealthTests(TestCase):
    def test_healthz_reports_ok(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "ok")
        self.assertEqual(data["database"], "ok")
        self.assertEqual(data["service"], "yakitori-platform")

    def test_healthz_matches_reverse(self):
        self.assertEqual(reverse("healthz"), "/healthz")


class PublicPageTests(TestCase):
    def test_home_page(self):
        response = self.client.get(reverse("web:home"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "local-first")

    def test_pricing_page(self):
        response = self.client.get(reverse("web:pricing"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "lifetime")

    def test_download_page(self):
        response = self.client.get(reverse("web:download"))
        self.assertEqual(response.status_code, 200)

    def test_privacy_and_terms_pages(self):
        self.assertEqual(self.client.get(reverse("web:privacy")).status_code, 200)
        self.assertEqual(self.client.get(reverse("web:terms")).status_code, 200)

    def test_unknown_page_returns_404(self):
        self.assertEqual(self.client.get("/does-not-exist/").status_code, 404)
