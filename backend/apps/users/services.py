from django.db import transaction

from .models import User, UserPreference


@transaction.atomic
def user_create(*, email: str, password: str, first_name: str = "", last_name: str = "") -> User:
    user = User.objects.create_user(
        email=email,
        password=password,
        first_name=first_name,
        last_name=last_name,
    )
    UserPreference.objects.create(user=user)
    return user
