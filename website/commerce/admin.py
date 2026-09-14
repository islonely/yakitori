from django.contrib import admin

from .models import PaymentPurchase, WebhookEvent


@admin.register(PaymentPurchase)
class PaymentPurchaseAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "provider", "status", "amount", "currency", "purchased_at")
    list_filter = ("provider", "status", "currency")
    search_fields = ("provider_purchase_id", "provider_checkout_id", "user__email")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(WebhookEvent)
class WebhookEventAdmin(admin.ModelAdmin):
    list_display = ("external_id", "provider", "event_type", "status", "received_at", "processed_at")
    list_filter = ("provider", "status", "event_type")
    search_fields = ("external_id",)
    readonly_fields = [field.name for field in WebhookEvent._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
