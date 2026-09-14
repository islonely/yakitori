(function () {
    "use strict";

    // Make HTMX send Django's CSRF token with every non-GET request.
    function csrfToken() {
        var meta = document.querySelector('meta[name="csrf-token"]');
        return meta ? meta.getAttribute("content") : "";
    }

    document.body.addEventListener("htmx:configRequest", function (event) {
        var token = csrfToken();
        if (token) {
            event.detail.headers["X-CSRFToken"] = token;
        }
        event.detail.headers["X-Requested-With"] = "XMLHttpRequest";
    });

    document.body.addEventListener("htmx:responseError", function (event) {
        var status = event.detail.xhr ? event.detail.xhr.status : 0;
        if (status === 403) {
            window.alert("Your session expired. Please reload the page and sign in again.");
        }
    });
})();
