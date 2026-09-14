from django.conf import settings


class SecurityHeadersMiddleware:
    """Attach a Content-Security-Policy and a small set of hardening headers.

    Django's SecurityMiddleware covers HSTS, nosniff, referrer policy, and SSL
    redirects. CSP is applied here because Django has no built-in CSP setting.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)

        policy = getattr(settings, "CONTENT_SECURITY_POLICY", "")
        if policy and "Content-Security-Policy" not in response:
            response["Content-Security-Policy"] = policy

        response.setdefault("Permissions-Policy", "interest-cohort=()")
        return response
