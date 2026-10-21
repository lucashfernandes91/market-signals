from rest_framework.views import exception_handler as drf_exception_handler


def exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    if response.status_code == 400:
        code = "validation_error"
    elif response.status_code == 503:
        code = getattr(exc, "default_code", "service_unavailable")
    else:
        code = "request_error"
    response.data = {
        "error": {
            "code": code,
            "message": "Não foi possível processar a solicitação.",
            "details": response.data,
        }
    }
    return response
