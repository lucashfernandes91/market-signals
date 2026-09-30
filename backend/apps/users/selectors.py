from .models import User


def user_get(*, user_id) -> User:
    return User.objects.get(id=user_id)
