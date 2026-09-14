from django.contrib import admin

from .models import AuditEvent


@admin.register(AuditEvent)
class AuditEventAdmin(admin.ModelAdmin):
    list_display = ("created_at", "event_type", "actor_user_id", "target_user_id", "source")
    list_filter = ("event_type", "source")
    search_fields = ("event_type", "source")
    date_hierarchy = "created_at"
    readonly_fields = [field.name for field in AuditEvent._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
