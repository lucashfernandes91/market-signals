from django.urls import path

from .views import (
    LoginView,
    MeView,
    PersonalSessionView,
    RefreshView,
    RegisterView,
    UserPreferenceView,
)

app_name = "users"

urlpatterns = [
    path("register/", RegisterView.as_view(), name="register"),
    path("personal-session/", PersonalSessionView.as_view(), name="personal-session"),
    path("token/", LoginView.as_view(), name="token-obtain-pair"),
    path("token/refresh/", RefreshView.as_view(), name="token-refresh"),
    path("me/", MeView.as_view(), name="me"),
    path("me/preferences/", UserPreferenceView.as_view(), name="preferences"),
]
