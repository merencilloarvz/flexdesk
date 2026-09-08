from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.serializers import as_serializer_error
from rest_framework.views import exception_handler as drf_exception_handler


def flexdesk_exception_handler(exc, context):
    """
    Every model in this project calls full_clean() inside save(), which raises
    Django's ValidationError. DRF does not recognise it and would return 500.
    Convert it to DRF's own ValidationError so it comes back as a normal 400
    with the same {"field": ["message"]} shape the client already handles.
    """
    if isinstance(exc, DjangoValidationError):
        exc = DRFValidationError(as_serializer_error(exc))
    return drf_exception_handler(exc, context)