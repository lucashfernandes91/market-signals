from rest_framework.views import exception_handler as drf_exception_handler


def exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    code = "validation_error" if response.status_code == 400 else "request_error"
    response.data = {
        "error": {
            "code": code,
            "message": "Não foi possível processar a solicitação.",
            "details": response.data,
        }
    }
    return response
