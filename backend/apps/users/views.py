from django.conf import settings
from rest_framework import generics, permissions
from rest_framework.exceptions import NotFound
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from core.throttling import LoginRateThrottle, RefreshRateThrottle

from .models import User, UserPreference
from .serializers import RegisterSerializer, UserPreferenceSerializer, UserSerializer


class RegisterView(generics.CreateAPIView):
    queryset = User.objects.none()
    serializer_class = RegisterSerializer
    permission_classes = (permissions.AllowAny,)


class LoginView(TokenObtainPairView):
    throttle_classes = (LoginRateThrottle,)


class RefreshView(TokenRefreshView):
    throttle_classes = (RefreshRateThrottle,)


class PersonalSessionView(APIView):
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        # Mantém a sessão automática isolada atrás da configuração do modo pessoal.
        if not settings.PERSONAL_MODE_ENABLED:
            raise NotFound()

        user, created = User.objects.get_or_create(
            email=settings.PERSONAL_MODE_EMAIL,
            defaults={"first_name": "Usuário", "last_name": "Pessoal"},
        )
        if created:
            user.set_unusable_password()
            user.save(update_fields=("password",))
        elif not user.is_active:
            user.is_active = True
            user.save(update_fields=("is_active",))

        UserPreference.objects.get_or_create(user=user)
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "account_id": str(user.id),
            }
        )


class MeView(generics.RetrieveAPIView):
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class UserPreferenceView(generics.RetrieveUpdateAPIView):
    serializer_class = UserPreferenceSerializer

    def get_object(self):
        preference, _ = UserPreference.objects.get_or_create(user=self.request.user)
        return preference
